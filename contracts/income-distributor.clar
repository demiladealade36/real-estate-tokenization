;; Income Distributor Contract for Real Estate Tokenization Platform
;; Handles rental income collection, distribution, and management fees

;; Constants
(define-constant ERR-UNAUTHORIZED (err u200))
(define-constant ERR-PROPERTY-NOT-FOUND (err u201))
(define-constant ERR-INSUFFICIENT-BALANCE (err u202))
(define-constant ERR-INVALID-AMOUNT (err u203))
(define-constant ERR-DISTRIBUTION-ALREADY-PROCESSED (err u204))
(define-constant ERR-NO-INCOME-TO-DISTRIBUTE (err u205))
(define-constant ERR-INVALID-FEE-RATE (err u206))
(define-constant ERR-PAYMENT-FAILED (err u207))
(define-constant ERR-INVALID-PERIOD (err u208))
(define-constant ERR-MAINTENANCE-RESERVE-LOW (err u209))

;; Income management constants
(define-constant MAX-MANAGEMENT-FEE u1000) ;; 10% maximum management fee
(define-constant MAINTENANCE-RESERVE-RATE u500) ;; 5% for maintenance reserve
(define-constant MIN-DISTRIBUTION-AMOUNT u1000000) ;; $10 minimum for distribution (in micro-units)
(define-constant BLOCKS-PER-MONTH u4320) ;; ~30 days worth of blocks
(define-constant MAX-EXPENSE-CATEGORIES u20)

;; Data Variables
(define-data-var total-income-collected uint u0)
(define-data-var total-distributed uint u0)
(define-data-var platform-fee-rate uint u250) ;; 2.5% platform fee
(define-data-var emergency-reserve uint u0)
(define-data-var distribution-counter uint u0)

;; Data Maps

;; Property income tracking
(define-map property-income
  { property-id: uint }
  {
    total-collected: uint,
    total-distributed: uint,
    pending-distribution: uint,
    maintenance-reserve: uint,
    management-fee-rate: uint,
    last-distribution-date: uint,
    monthly-rent: uint,
    occupancy-rate: uint, ;; Percentage (0-10000 for 0-100%)
    property-manager: principal
  }
)

;; Monthly income records
(define-map monthly-income-reports
  { property-id: uint, period: uint }
  {
    rent-collected: uint,
    late-fees: uint,
    other-income: uint,
    total-income: uint,
    collection-date: uint,
    occupancy-days: uint,
    tenant-count: uint
  }
)

;; Distribution records
(define-map income-distributions
  { distribution-id: uint }
  {
    property-id: uint,
    period: uint,
    gross-income: uint,
    management-fee: uint,
    platform-fee: uint,
    maintenance-reserve: uint,
    net-distributable: uint,
    distribution-date: uint,
    total-shareholders: uint,
    processed: bool
  }
)

;; Individual shareholder distributions
(define-map shareholder-distributions
  { distribution-id: uint, shareholder: principal }
  {
    property-id: uint,
    shares-owned: uint,
    distribution-amount: uint,
    claimed: bool,
    claim-date: uint
  }
)

;; Property expenses tracking
(define-map property-expenses
  { property-id: uint, expense-id: uint }
  {
    expense-type: (string-ascii 50),
    amount: uint,
    description: (string-ascii 200),
    vendor: (string-ascii 100),
    expense-date: uint,
    approved-by: principal,
    category: (string-ascii 30)
  }
)

;; Maintenance reserve allocations
(define-map maintenance-reserves
  { property-id: uint }
  {
    current-balance: uint,
    target-balance: uint,
    total-contributions: uint,
    total-expenses: uint,
    last-updated: uint
  }
)

;; Property manager assignments
(define-map property-managers
  { manager-id: uint }
  {
    manager-address: principal,
    manager-name: (string-ascii 100),
    fee-rate: uint,
    properties-managed: uint,
    total-collected: uint,
    registration-date: uint,
    is-active: bool
  }
)

;; Expense approvers
(define-map expense-approvers
  { property-id: uint, approver: principal }
  {
    approval-limit: uint,
    can-approve-maintenance: bool,
    can-approve-capital: bool,
    assigned-date: uint
  }
)

;; Tax reporting data
(define-map annual-tax-reports
  { property-id: uint, tax-year: uint }
  {
    total-rental-income: uint,
    total-expenses: uint,
    depreciation-claimed: uint,
    net-income: uint,
    distributions-made: uint,
    report-generated: bool
  }
)

;; Private Functions

;; Calculate management fee
(define-private (calculate-management-fee (gross-income uint) (fee-rate uint))
  (/ (* gross-income fee-rate) u10000)
)

;; Calculate platform fee
(define-private (calculate-platform-fee (amount uint))
  (/ (* amount (var-get platform-fee-rate)) u10000)
)

;; Calculate maintenance reserve contribution
(define-private (calculate-maintenance-reserve (gross-income uint))
  (/ (* gross-income MAINTENANCE-RESERVE-RATE) u10000)
)

;; Get shareholder count for property (simplified)
(define-private (get-shareholder-count (property-id uint))
  ;; In practice, would query from property-tokenizer contract
  u10 ;; Simplified placeholder
)

;; Calculate individual distribution based on shares
(define-private (calculate-share-distribution (net-amount uint) (shares-owned uint) (total-shares uint))
  (/ (* net-amount shares-owned) total-shares)
)

;; Validate expense category
(define-private (is-valid-expense-category (category (string-ascii 30)))
  (or 
    (is-eq category "maintenance")
    (is-eq category "repairs")
    (is-eq category "utilities")
    (is-eq category "insurance")
    (is-eq category "property-tax")
    (is-eq category "legal")
    (is-eq category "management")
    (is-eq category "capital-improvement")
  )
)

;; Check if maintenance reserve is sufficient
(define-private (check-maintenance-reserve-sufficient (property-id uint))
  (match (map-get? maintenance-reserves { property-id: property-id })
    reserve-data
    (>= (get current-balance reserve-data) 
        (/ (get target-balance reserve-data) u2)) ;; At least 50% of target
    false
  )
)

;; Update income statistics
(define-private (update-income-stats (amount uint))
  (var-set total-income-collected (+ (var-get total-income-collected) amount))
)

;; Public Functions

;; Register property for income management
(define-public (register-property-for-income 
  (property-id uint)
  (monthly-rent uint)
  (management-fee-rate uint)
  (property-manager principal)
  )
  (begin
    (asserts! (<= management-fee-rate MAX-MANAGEMENT-FEE) ERR-INVALID-FEE-RATE)
    (asserts! (> monthly-rent u0) ERR-INVALID-AMOUNT)
    
    ;; Initialize property income tracking
    (map-set property-income
      { property-id: property-id }
      {
        total-collected: u0,
        total-distributed: u0,
        pending-distribution: u0,
        maintenance-reserve: u0,
        management-fee-rate: management-fee-rate,
        last-distribution-date: u0,
        monthly-rent: monthly-rent,
        occupancy-rate: u10000, ;; 100% initial occupancy
        property-manager: property-manager
      }
    )
    
    ;; Initialize maintenance reserve
    (map-set maintenance-reserves
      { property-id: property-id }
      {
        current-balance: u0,
        target-balance: (* monthly-rent u6), ;; 6 months of rent as target
        total-contributions: u0,
        total-expenses: u0,
        last-updated: block-height
      }
    )
    
    (ok property-id)
  )
)

;; Record monthly rental income
(define-public (record-monthly-income
  (property-id uint)
  (rent-collected uint)
  (late-fees uint)
  (other-income uint)
  (occupancy-days uint)
  (tenant-count uint)
  )
  (let
    (
      (period (/ block-height BLOCKS-PER-MONTH))
      (total-income (+ (+ rent-collected late-fees) other-income))
      (property-data (unwrap! (map-get? property-income { property-id: property-id }) ERR-PROPERTY-NOT-FOUND))
    )
    (asserts! (> total-income u0) ERR-INVALID-AMOUNT)
    (asserts! (<= occupancy-days u30) ERR-INVALID-PERIOD) ;; Max 30 days per month
    
    ;; Record monthly income report
    (map-set monthly-income-reports
      { property-id: property-id, period: period }
      {
        rent-collected: rent-collected,
        late-fees: late-fees,
        other-income: other-income,
        total-income: total-income,
        collection-date: block-height,
        occupancy-days: occupancy-days,
        tenant-count: tenant-count
      }
    )
    
    ;; Update property income totals
    (map-set property-income
      { property-id: property-id }
      (merge property-data {
        total-collected: (+ (get total-collected property-data) total-income),
        pending-distribution: (+ (get pending-distribution property-data) total-income),
        occupancy-rate: (/ (* occupancy-days u10000) u30) ;; Convert to percentage
      })
    )
    
    ;; Update global statistics
    (update-income-stats total-income)
    
    (ok total-income)
  )
)

;; Process monthly income distribution
(define-public (process-income-distribution (property-id uint) (period uint))
  (let
    (
      (distribution-id (+ (var-get distribution-counter) u1))
      (property-data (unwrap! (map-get? property-income { property-id: property-id }) ERR-PROPERTY-NOT-FOUND))
      (income-report (unwrap! (map-get? monthly-income-reports { property-id: property-id, period: period }) ERR-NO-INCOME-TO-DISTRIBUTE))
      (gross-income (get total-income income-report))
    )
    (asserts! (>= gross-income MIN-DISTRIBUTION-AMOUNT) ERR-NO-INCOME-TO-DISTRIBUTE)
    (asserts! (> (get pending-distribution property-data) u0) ERR-NO-INCOME-TO-DISTRIBUTE)
    
    (let
      (
        (management-fee (calculate-management-fee gross-income (get management-fee-rate property-data)))
        (platform-fee (calculate-platform-fee gross-income))
        (maintenance-contribution (calculate-maintenance-reserve gross-income))
        (net-distributable (- (- (- gross-income management-fee) platform-fee) maintenance-contribution))
        (shareholder-count (get-shareholder-count property-id))
      )
      ;; Create distribution record
      (map-set income-distributions
        { distribution-id: distribution-id }
        {
          property-id: property-id,
          period: period,
          gross-income: gross-income,
          management-fee: management-fee,
          platform-fee: platform-fee,
          maintenance-reserve: maintenance-contribution,
          net-distributable: net-distributable,
          distribution-date: block-height,
          total-shareholders: shareholder-count,
          processed: false
        }
      )
      
      ;; Update maintenance reserve
      (let
        (
          (reserve-data (unwrap-panic (map-get? maintenance-reserves { property-id: property-id })))
        )
        (map-set maintenance-reserves
          { property-id: property-id }
          (merge reserve-data {
            current-balance: (+ (get current-balance reserve-data) maintenance-contribution),
            total-contributions: (+ (get total-contributions reserve-data) maintenance-contribution),
            last-updated: block-height
          })
        )
      )
      
      ;; Update property income data
      (map-set property-income
        { property-id: property-id }
        (merge property-data {
          pending-distribution: (- (get pending-distribution property-data) gross-income),
          total-distributed: (+ (get total-distributed property-data) net-distributable),
          last-distribution-date: block-height
        })
      )
      
      ;; Update global statistics
      (var-set total-distributed (+ (var-get total-distributed) net-distributable))
      (var-set distribution-counter distribution-id)
      
      (ok {
        distribution-id: distribution-id,
        net-distributable: net-distributable,
        management-fee: management-fee,
        platform-fee: platform-fee,
        maintenance-reserve: maintenance-contribution
      })
    )
  )
)

;; Claim individual distribution
(define-public (claim-distribution (distribution-id uint) (shares-owned uint) (total-shares uint))
  (let
    (
      (distribution-data (unwrap! (map-get? income-distributions { distribution-id: distribution-id }) ERR-DISTRIBUTION-ALREADY-PROCESSED))
      (existing-claim (map-get? shareholder-distributions { distribution-id: distribution-id, shareholder: tx-sender }))
    )
    (asserts! (is-none existing-claim) ERR-DISTRIBUTION-ALREADY-PROCESSED)
    (asserts! (> shares-owned u0) ERR-INVALID-AMOUNT)
    (asserts! (> total-shares u0) ERR-INVALID-AMOUNT)
    
    (let
      (
        (distribution-amount (calculate-share-distribution 
                             (get net-distributable distribution-data) 
                             shares-owned 
                             total-shares))
      )
      (asserts! (> distribution-amount u0) ERR-INVALID-AMOUNT)
      
      ;; Record shareholder distribution
      (map-set shareholder-distributions
        { distribution-id: distribution-id, shareholder: tx-sender }
        {
          property-id: (get property-id distribution-data),
          shares-owned: shares-owned,
          distribution-amount: distribution-amount,
          claimed: true,
          claim-date: block-height
        }
      )
      
      ;; In production, would transfer tokens here
      ;; (try! (as-contract (stx-transfer? distribution-amount tx-sender tx-sender)))
      
      (ok distribution-amount)
    )
  )
)

;; Record property expense
(define-public (record-expense
  (property-id uint)
  (expense-type (string-ascii 50))
  (amount uint)
  (description (string-ascii 200))
  (vendor (string-ascii 100))
  (category (string-ascii 30))
  )
  (let
    (
      (expense-id (+ block-height (hash-bytes (unwrap-panic (to-consensus-buff? tx-sender)))))
      (property-data (unwrap! (map-get? property-income { property-id: property-id }) ERR-PROPERTY-NOT-FOUND))
    )
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (is-valid-expense-category category) ERR-INVALID-AMOUNT)
    
    ;; Check if maintenance expense and sufficient reserve
    (if (is-eq category "maintenance")
      (asserts! (check-maintenance-reserve-sufficient property-id) ERR-MAINTENANCE-RESERVE-LOW)
      true
    )
    
    ;; Record expense
    (map-set property-expenses
      { property-id: property-id, expense-id: expense-id }
      {
        expense-type: expense-type,
        amount: amount,
        description: description,
        vendor: vendor,
        expense-date: block-height,
        approved-by: tx-sender,
        category: category
      }
    )
    
    ;; Update maintenance reserve if applicable
    (if (is-eq category "maintenance")
      (let
        (
          (reserve-data (unwrap-panic (map-get? maintenance-reserves { property-id: property-id })))
        )
        (map-set maintenance-reserves
          { property-id: property-id }
          (merge reserve-data {
            current-balance: (- (get current-balance reserve-data) amount),
            total-expenses: (+ (get total-expenses reserve-data) amount),
            last-updated: block-height
          })
        )
      )
      true
    )
    
    (ok expense-id)
  )
)

;; Update management fee rate
(define-public (update-management-fee (property-id uint) (new-fee-rate uint))
  (let
    (
      (property-data (unwrap! (map-get? property-income { property-id: property-id }) ERR-PROPERTY-NOT-FOUND))
    )
    ;; Only property manager can update fee
    (asserts! (is-eq tx-sender (get property-manager property-data)) ERR-UNAUTHORIZED)
    (asserts! (<= new-fee-rate MAX-MANAGEMENT-FEE) ERR-INVALID-FEE-RATE)
    
    (map-set property-income
      { property-id: property-id }
      (merge property-data { management-fee-rate: new-fee-rate })
    )
    
    (ok new-fee-rate)
  )
)

;; Generate annual tax report
(define-public (generate-annual-tax-report (property-id uint) (tax-year uint))
  (let
    (
      (property-data (unwrap! (map-get? property-income { property-id: property-id }) ERR-PROPERTY-NOT-FOUND))
    )
    ;; Simplified tax calculation - in practice would be more complex
    (let
      (
        (total-income (get total-collected property-data))
        (total-expenses u0) ;; Would calculate from expense records
        (net-income (- total-income total-expenses))
      )
      (map-set annual-tax-reports
        { property-id: property-id, tax-year: tax-year }
        {
          total-rental-income: total-income,
          total-expenses: total-expenses,
          depreciation-claimed: u0,
          net-income: net-income,
          distributions-made: (get total-distributed property-data),
          report-generated: true
        }
      )
      
      (ok net-income)
    )
  )
)

;; Read-only Functions

;; Get property income summary
(define-read-only (get-property-income (property-id uint))
  (map-get? property-income { property-id: property-id })
)

;; Get monthly income report
(define-read-only (get-monthly-report (property-id uint) (period uint))
  (map-get? monthly-income-reports { property-id: property-id, period: period })
)

;; Get distribution details
(define-read-only (get-distribution (distribution-id uint))
  (map-get? income-distributions { distribution-id: distribution-id })
)

;; Get shareholder distribution
(define-read-only (get-shareholder-distribution (distribution-id uint) (shareholder principal))
  (map-get? shareholder-distributions { distribution-id: distribution-id, shareholder: shareholder })
)

;; Get maintenance reserve status
(define-read-only (get-maintenance-reserve (property-id uint))
  (map-get? maintenance-reserves { property-id: property-id })
)

;; Get property expense
(define-read-only (get-expense (property-id uint) (expense-id uint))
  (map-get? property-expenses { property-id: property-id, expense-id: expense-id })
)

;; Get annual tax report
(define-read-only (get-tax-report (property-id uint) (tax-year uint))
  (map-get? annual-tax-reports { property-id: property-id, tax-year: tax-year })
)

;; Calculate estimated monthly distribution
(define-read-only (estimate-monthly-distribution (property-id uint) (gross-income uint))
  (match (map-get? property-income { property-id: property-id })
    property-data
    (let
      (
        (management-fee (calculate-management-fee gross-income (get management-fee-rate property-data)))
        (platform-fee (calculate-platform-fee gross-income))
        (maintenance-contribution (calculate-maintenance-reserve gross-income))
        (net-distributable (- (- (- gross-income management-fee) platform-fee) maintenance-contribution))
      )
      (ok {
        gross-income: gross-income,
        management-fee: management-fee,
        platform-fee: platform-fee,
        maintenance-reserve: maintenance-contribution,
        net-distributable: net-distributable,
        distribution-per-share: (/ net-distributable u1000000) ;; Assuming 1M shares per property
      })
    )
    (err ERR-PROPERTY-NOT-FOUND)
  )
)

;; Get platform income statistics
(define-read-only (get-platform-income-stats)
  {
    total-income-collected: (var-get total-income-collected),
    total-distributed: (var-get total-distributed),
    platform-fee-rate: (var-get platform-fee-rate),
    emergency-reserve: (var-get emergency-reserve),
    distributions-processed: (var-get distribution-counter)
  }
)

;; Get property performance metrics
(define-read-only (get-property-performance-metrics (property-id uint))
  (match (map-get? property-income { property-id: property-id })
    property-data
    (let
      (
        (total-collected (get total-collected property-data))
        (total-distributed (get total-distributed property-data))
        (monthly-rent (get monthly-rent property-data))
        (occupancy-rate (get occupancy-rate property-data))
      )
      (ok {
        total-collected: total-collected,
        total-distributed: total-distributed,
        collection-efficiency: (if (> monthly-rent u0) (/ (* total-collected u10000) (* monthly-rent u12)) u0),
        occupancy-rate: occupancy-rate,
        average-monthly-income: (if (> u12 u0) (/ total-collected u12) u0),
        distribution-ratio: (if (> total-collected u0) (/ (* total-distributed u10000) total-collected) u0)
      })
    )
    (err ERR-PROPERTY-NOT-FOUND)
  )
)

;; Check distribution eligibility
(define-read-only (check-distribution-eligibility (property-id uint))
  (match (map-get? property-income { property-id: property-id })
    property-data
    (let
      (
        (pending-amount (get pending-distribution property-data))
        (last-distribution (get last-distribution-date property-data))
        (blocks-since-last (- block-height last-distribution))
      )
      (ok {
        has-pending-income: (>= pending-amount MIN-DISTRIBUTION-AMOUNT),
        pending-amount: pending-amount,
        blocks-since-last-distribution: blocks-since-last,
        eligible-for-distribution: (and 
                                   (>= pending-amount MIN-DISTRIBUTION-AMOUNT)
                                   (>= blocks-since-last BLOCKS-PER-MONTH))
      })
    )
    (err ERR-PROPERTY-NOT-FOUND)
  )
)

;; Calculate total claimable amount for shareholder
(define-read-only (calculate-total-claimable (shareholder principal) (property-id uint) (shares-owned uint) (total-shares uint))
  ;; Simplified - would iterate through all unclaimed distributions
  (let
    (
      (distribution-ids (list u1 u2 u3 u4 u5)) ;; Would be dynamic in production
    )
    (fold calculate-claimable-for-distribution distribution-ids u0)
  )
)

(define-private (calculate-claimable-for-distribution (distribution-id uint) (current-total uint))
  ;; Simplified calculation - would check if already claimed
  (match (map-get? income-distributions { distribution-id: distribution-id })
    distribution-data
    (+ current-total (/ (get net-distributable distribution-data) u100)) ;; Simplified
    current-total
  )
)


;; title: income-distributor
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

