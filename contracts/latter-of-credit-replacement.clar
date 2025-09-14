(define-constant CONTRACT-OWNER tx-sender)

(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-ALREADY-EXISTS (err u101))
(define-constant ERR-NOT-FOUND (err u102))
(define-constant ERR-INVALID-STATE (err u103))
(define-constant ERR-INSUFFICIENT-FUNDS (err u104))
(define-constant ERR-EXPIRED (err u105))

(define-constant STATE-CREATED u0)
(define-constant STATE-FUNDED u1)
(define-constant STATE-DELIVERED u2)
(define-constant STATE-COMPLETED u3)
(define-constant STATE-CANCELLED u4)

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
