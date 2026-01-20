(define-constant CONTRACT-OWNER tx-sender)

(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-ALREADY-EXISTS (err u101))
(define-constant ERR-NOT-FOUND (err u102))
(define-constant ERR-INVALID-STATE (err u103))
(define-constant ERR-INSUFFICIENT-FUNDS (err u104))
(define-constant ERR-EXPIRED (err u105))
(define-constant ERR-DISPUTE-ACTIVE (err u106))
(define-constant ERR-NO-DISPUTE (err u107))
(define-constant ERR-DISPUTE-TIMEOUT (err u108))
(define-constant ERR-INVALID-MILESTONE (err u109))
(define-constant ERR-MILESTONE-ALREADY-PAID (err u110))
(define-constant ERR-INVALID-PERCENTAGE (err u111))

(define-constant STATE-CREATED u0)
(define-constant STATE-FUNDED u1)
(define-constant STATE-DELIVERED u2)
(define-constant STATE-COMPLETED u3)
(define-constant STATE-CANCELLED u4)
(define-constant STATE-DISPUTED u5)

(define-data-var lc-counter uint u0)

(define-map letters-of-credit
  { lc-id: uint }
  {
    buyer: principal,
    seller: principal,
    amount: uint,
    delivery-deadline: uint,
    state: uint,
    created-at: uint,
    delivery-confirmer: (optional principal)
  }
)

(define-map lc-funds
  { lc-id: uint }
  { amount: uint }
)

(define-map disputes
  { lc-id: uint }
  {
    raised-by: principal,
    raised-at: uint,
    reason: (string-ascii 256),
    resolution-deadline: uint,
    resolved: bool
  }
)

(define-map milestones
  { lc-id: uint, milestone-id: uint }
  {
    description: (string-ascii 256),
    percentage: uint,
    completed: bool,
    paid: bool
  }
)

(define-map milestone-counter
  { lc-id: uint }
  { count: uint }
)

(define-private (get-next-lc-id)
  (let ((current-id (var-get lc-counter)))
    (var-set lc-counter (+ current-id u1))
    current-id
  )
)

(define-private (is-lc-expired (deadline uint))
  (> stacks-block-height deadline)
)

(define-public (create-letter-of-credit 
  (seller principal)
  (amount uint)
  (delivery-deadline uint)
  (delivery-confirmer (optional principal)))
  (let ((lc-id (get-next-lc-id)))
    (asserts! (> amount u0) ERR-INSUFFICIENT-FUNDS)
    (asserts! (> delivery-deadline stacks-block-height) ERR-INVALID-STATE)
    
    (map-set letters-of-credit
      { lc-id: lc-id }
      {
        buyer: tx-sender,
        seller: seller,
        amount: amount,
        delivery-deadline: delivery-deadline,
        state: STATE-CREATED,
        created-at: stacks-block-height,
        delivery-confirmer: delivery-confirmer
      }
    )
    
    (ok lc-id)
  )
)

(define-public (fund-letter-of-credit (lc-id uint))
  (let ((lc-data (unwrap! (map-get? letters-of-credit { lc-id: lc-id }) ERR-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get buyer lc-data)) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get state lc-data) STATE-CREATED) ERR-INVALID-STATE)
    (asserts! (not (is-lc-expired (get delivery-deadline lc-data))) ERR-EXPIRED)
    
    (try! (stx-transfer? (get amount lc-data) tx-sender (as-contract tx-sender)))
    
    (map-set letters-of-credit
      { lc-id: lc-id }
      (merge lc-data { state: STATE-FUNDED })
    )
    
    (map-set lc-funds
      { lc-id: lc-id }
      { amount: (get amount lc-data) }
    )
    
    (ok true)
  )
)

(define-public (confirm-delivery (lc-id uint))
  (let ((lc-data (unwrap! (map-get? letters-of-credit { lc-id: lc-id }) ERR-NOT-FOUND)))
    (asserts! (is-eq (get state lc-data) STATE-FUNDED) ERR-INVALID-STATE)
    (asserts! (not (is-lc-expired (get delivery-deadline lc-data))) ERR-EXPIRED)
    
    (asserts! 
      (or 
        (is-eq tx-sender (get seller lc-data))
        (is-eq tx-sender (get buyer lc-data))
        (match (get delivery-confirmer lc-data)
          confirmer (is-eq tx-sender confirmer)
          false
        )
      )
      ERR-UNAUTHORIZED
    )
    
    (map-set letters-of-credit
      { lc-id: lc-id }
      (merge lc-data { state: STATE-DELIVERED })
    )
    
    (ok true)
  )
)

(define-public (release-payment (lc-id uint))
  (let (
    (lc-data (unwrap! (map-get? letters-of-credit { lc-id: lc-id }) ERR-NOT-FOUND))
    (fund-data (unwrap! (map-get? lc-funds { lc-id: lc-id }) ERR-NOT-FOUND))
  )
    (asserts! (is-eq (get state lc-data) STATE-DELIVERED) ERR-INVALID-STATE)
    
    (asserts! 
      (or 
        (is-eq tx-sender (get buyer lc-data))
        (is-eq tx-sender (get seller lc-data))
      )
      ERR-UNAUTHORIZED
    )
    
    (try! (as-contract (stx-transfer? (get amount fund-data) tx-sender (get seller lc-data))))
    
    (map-set letters-of-credit
      { lc-id: lc-id }
      (merge lc-data { state: STATE-COMPLETED })
    )
    
    (map-delete lc-funds { lc-id: lc-id })
    
    (ok true)
  )
)

(define-public (cancel-letter-of-credit (lc-id uint))
  (let (
    (lc-data (unwrap! (map-get? letters-of-credit { lc-id: lc-id }) ERR-NOT-FOUND))
    (fund-data (map-get? lc-funds { lc-id: lc-id }))
  )
    (asserts! (is-eq tx-sender (get buyer lc-data)) ERR-UNAUTHORIZED)
    (asserts! 
      (or 
        (is-eq (get state lc-data) STATE-CREATED)
        (and 
          (is-eq (get state lc-data) STATE-FUNDED)
          (is-lc-expired (get delivery-deadline lc-data))
        )
      )
      ERR-INVALID-STATE
    )
    
    (match fund-data
      funds (try! (as-contract (stx-transfer? (get amount funds) tx-sender (get buyer lc-data))))
      true
    )
    
    (map-set letters-of-credit
      { lc-id: lc-id }
      (merge lc-data { state: STATE-CANCELLED })
    )
    
    (map-delete lc-funds { lc-id: lc-id })
    
    (ok true)
  )
)

(define-read-only (get-letter-of-credit (lc-id uint))
  (map-get? letters-of-credit { lc-id: lc-id })
)

(define-read-only (get-lc-funds (lc-id uint))
  (map-get? lc-funds { lc-id: lc-id })
)

(define-read-only (get-current-lc-counter)
  (var-get lc-counter)
)

(define-read-only (is-buyer (lc-id uint) (user principal))
  (match (map-get? letters-of-credit { lc-id: lc-id })
    lc-data (is-eq user (get buyer lc-data))
    false
  )
)

(define-read-only (is-seller (lc-id uint) (user principal))
  (match (map-get? letters-of-credit { lc-id: lc-id })
    lc-data (is-eq user (get seller lc-data))
    false
  )
)

(define-read-only (get-lc-state (lc-id uint))
  (match (map-get? letters-of-credit { lc-id: lc-id })
    lc-data (some (get state lc-data))
    none
  )
)

(define-read-only (is-lc-active (lc-id uint))
  (match (map-get? letters-of-credit { lc-id: lc-id })
    lc-data 
      (and 
        (< (get state lc-data) STATE-COMPLETED)
        (not (is-lc-expired (get delivery-deadline lc-data)))
      )
    false
  )
)

(define-public (raise-dispute (lc-id uint) (reason (string-ascii 256)))
  (let ((lc-data (unwrap! (map-get? letters-of-credit { lc-id: lc-id }) ERR-NOT-FOUND)))
    (asserts! 
      (or 
        (is-eq (get state lc-data) STATE-FUNDED)
        (is-eq (get state lc-data) STATE-DELIVERED)
      )
      ERR-INVALID-STATE
    )
    (asserts! (is-none (map-get? disputes { lc-id: lc-id })) ERR-DISPUTE-ACTIVE)
    (asserts! 
      (or 
        (is-eq tx-sender (get buyer lc-data))
        (is-eq tx-sender (get seller lc-data))
      )
      ERR-UNAUTHORIZED
    )
    
    (map-set disputes
      { lc-id: lc-id }
      {
        raised-by: tx-sender,
        raised-at: stacks-block-height,
        reason: reason,
        resolution-deadline: (+ stacks-block-height u1440),
        resolved: false
      }
    )
    
    (map-set letters-of-credit
      { lc-id: lc-id }
      (merge lc-data { state: STATE-DISPUTED })
    )
    
    (ok true)
  )
)

(define-public (resolve-dispute (lc-id uint) (favor-buyer bool))
  (let (
    (lc-data (unwrap! (map-get? letters-of-credit { lc-id: lc-id }) ERR-NOT-FOUND))
    (dispute-data (unwrap! (map-get? disputes { lc-id: lc-id }) ERR-NO-DISPUTE))
    (fund-data (unwrap! (map-get? lc-funds { lc-id: lc-id }) ERR-NOT-FOUND))
  )
    (asserts! (is-eq (get state lc-data) STATE-DISPUTED) ERR-INVALID-STATE)
    (asserts! (not (get resolved dispute-data)) ERR-INVALID-STATE)
    
    (asserts! 
      (or 
        (match (get delivery-confirmer lc-data)
          confirmer (is-eq tx-sender confirmer)
          false
        )
        (and 
          (> stacks-block-height (get resolution-deadline dispute-data))
          (or 
            (is-eq tx-sender (get buyer lc-data))
            (is-eq tx-sender (get seller lc-data))
          )
        )
      )
      ERR-UNAUTHORIZED
    )
    
    (if favor-buyer
      (try! (as-contract (stx-transfer? (get amount fund-data) tx-sender (get buyer lc-data))))
      (try! (as-contract (stx-transfer? (get amount fund-data) tx-sender (get seller lc-data))))
    )
    
    (map-set disputes
      { lc-id: lc-id }
      (merge dispute-data { resolved: true })
    )
    
    (map-set letters-of-credit
      { lc-id: lc-id }
      (merge lc-data { state: STATE-COMPLETED })
    )
    
    (map-delete lc-funds { lc-id: lc-id })
    
    (ok true)
  )
)

(define-read-only (get-dispute (lc-id uint))
  (map-get? disputes { lc-id: lc-id })
)

(define-read-only (is-dispute-expired (lc-id uint))
  (match (map-get? disputes { lc-id: lc-id })
    dispute-data (> stacks-block-height (get resolution-deadline dispute-data))
    false
  )
)

(define-public (add-milestone (lc-id uint) (description (string-ascii 256)) (percentage uint))
  (let (
    (lc-data (unwrap! (map-get? letters-of-credit { lc-id: lc-id }) ERR-NOT-FOUND))
    (counter-data (default-to { count: u0 } (map-get? milestone-counter { lc-id: lc-id })))
    (milestone-id (get count counter-data))
  )
    (asserts! (is-eq tx-sender (get buyer lc-data)) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get state lc-data) STATE-CREATED) ERR-INVALID-STATE)
    (asserts! (and (> percentage u0) (<= percentage u100)) ERR-INVALID-PERCENTAGE)
    
    (map-set milestones
      { lc-id: lc-id, milestone-id: milestone-id }
      {
        description: description,
        percentage: percentage,
        completed: false,
        paid: false
      }
    )
    
    (map-set milestone-counter
      { lc-id: lc-id }
      { count: (+ milestone-id u1) }
    )
    
    (ok milestone-id)
  )
)

(define-public (complete-milestone (lc-id uint) (milestone-id uint))
  (let (
    (lc-data (unwrap! (map-get? letters-of-credit { lc-id: lc-id }) ERR-NOT-FOUND))
    (milestone-data (unwrap! (map-get? milestones { lc-id: lc-id, milestone-id: milestone-id }) ERR-INVALID-MILESTONE))
  )
    (asserts! (is-eq (get state lc-data) STATE-FUNDED) ERR-INVALID-STATE)
    (asserts! (not (get completed milestone-data)) ERR-INVALID-STATE)
    
    (asserts! 
      (or 
        (is-eq tx-sender (get seller lc-data))
        (is-eq tx-sender (get buyer lc-data))
        (match (get delivery-confirmer lc-data)
          confirmer (is-eq tx-sender confirmer)
          false
        )
      )
      ERR-UNAUTHORIZED
    )
    
    (map-set milestones
      { lc-id: lc-id, milestone-id: milestone-id }
      (merge milestone-data { completed: true })
    )
    
    (ok true)
  )
)

(define-public (release-milestone-payment (lc-id uint) (milestone-id uint))
  (let (
    (lc-data (unwrap! (map-get? letters-of-credit { lc-id: lc-id }) ERR-NOT-FOUND))
    (milestone-data (unwrap! (map-get? milestones { lc-id: lc-id, milestone-id: milestone-id }) ERR-INVALID-MILESTONE))
    (fund-data (unwrap! (map-get? lc-funds { lc-id: lc-id }) ERR-NOT-FOUND))
    (payment-amount (/ (* (get amount lc-data) (get percentage milestone-data)) u100))
  )
    (asserts! (is-eq (get state lc-data) STATE-FUNDED) ERR-INVALID-STATE)
    (asserts! (get completed milestone-data) ERR-INVALID-STATE)
    (asserts! (not (get paid milestone-data)) ERR-MILESTONE-ALREADY-PAID)
    (asserts! 
      (or 
        (is-eq tx-sender (get buyer lc-data))
        (is-eq tx-sender (get seller lc-data))
      )
      ERR-UNAUTHORIZED
    )
    
    (try! (as-contract (stx-transfer? payment-amount tx-sender (get seller lc-data))))
    
    (map-set milestones
      { lc-id: lc-id, milestone-id: milestone-id }
      (merge milestone-data { paid: true })
    )
    
    (let ((remaining-funds (- (get amount fund-data) payment-amount)))
      (if (> remaining-funds u0)
        (map-set lc-funds { lc-id: lc-id } { amount: remaining-funds })
        (map-delete lc-funds { lc-id: lc-id })
      )
    )
    
    (ok payment-amount)
  )
)

(define-read-only (get-milestone (lc-id uint) (milestone-id uint))
  (map-get? milestones { lc-id: lc-id, milestone-id: milestone-id })
)

(define-read-only (get-milestone-count (lc-id uint))
  (match (map-get? milestone-counter { lc-id: lc-id })
    counter-data (some (get count counter-data))
    (some u0)
  )
)

(define-read-only (get-lc-overview (lc-id uint))
  (match (map-get? letters-of-credit { lc-id: lc-id })
    lc-data
      (let (
        (funds (default-to { amount: u0 } (map-get? lc-funds { lc-id: lc-id })))
        (dispute-opt (map-get? disputes { lc-id: lc-id }))
        (counter-opt (map-get? milestone-counter { lc-id: lc-id }))
        (milestone-count (match counter-opt counter-data (get count counter-data) u0))
        (has-dispute (is-some dispute-opt))
        (dispute-active (match dispute-opt dispute-data (not (get resolved dispute-data)) false))
        (dispute-deadline (match dispute-opt dispute-data (some (get resolution-deadline dispute-data)) none))
      )
        (ok
          {
            lc-id: lc-id,
            buyer: (get buyer lc-data),
            seller: (get seller lc-data),
            amount: (get amount lc-data),
            locked-amount: (get amount funds),
            state: (get state lc-data),
            is-active: (is-lc-active lc-id),
            has-dispute: has-dispute,
            dispute-active: dispute-active,
            dispute-deadline: dispute-deadline,
            milestone-count: milestone-count,
            created-at: (get created-at lc-data),
            delivery-deadline: (get delivery-deadline lc-data)
          }
        )
      )
    ERR-NOT-FOUND
  )
)
