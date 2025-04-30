(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_ALREADY_REGISTERED (err u101))
(define-constant ERR_NOT_REGISTERED (err u102))
(define-constant ERR_PAPER_EXISTS (err u103))
(define-constant ERR_PAPER_NOT_FOUND (err u104))
(define-constant ERR_ALREADY_REVIEWED (err u105))
(define-constant ERR_SELF_REVIEW (err u106))
(define-constant ERR_INSUFFICIENT_BALANCE (err u107))
(define-constant ERR_INVALID_AMOUNT (err u108))
(define-constant ERR_REVIEW_NOT_FOUND (err u109))

(define-constant ADMIN_ROLE u1)
(define-constant RESEARCHER_ROLE u2)
(define-constant REVIEWER_ROLE u3)

(define-fungible-token review-token)

(define-data-var token-uri (string-utf8 256) u"https://review-incentive.org/token-metadata")
(define-data-var admin principal tx-sender)

(define-map users
  { user: principal }
  { role: uint, reputation: uint, registered: bool }
)

(define-map papers
  { paper-id: uint }
  { 
    author: principal,
    title: (string-utf8 100),
    abstract: (string-utf8 500),
    reward-amount: uint,
    status: (string-ascii 20),
    review-count: uint
  }
)

(define-map reviews
  { paper-id: uint, reviewer: principal }
  {
    rating: uint,
    comment: (string-utf8 500),
    timestamp: uint,
    rewarded: bool
  }
)

(define-data-var paper-id-nonce uint u0)

(define-read-only (get-token-uri)
  (var-get token-uri)
)

(define-read-only (get-admin)
  (var-get admin)
)

(define-read-only (get-user-info (user principal))
  (default-to 
    { role: u0, reputation: u0, registered: false }
    (map-get? users { user: user })
  )
)

(define-read-only (get-paper (paper-id uint))
  (map-get? papers { paper-id: paper-id })
)

(define-read-only (get-review (paper-id uint) (reviewer principal))
  (map-get? reviews { paper-id: paper-id, reviewer: reviewer })
)

(define-read-only (get-balance (account principal))
  (ft-get-balance review-token account)
)

(define-public (set-admin (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) ERR_UNAUTHORIZED)
    (var-set admin new-admin)
    (ok true)
  )
)

(define-public (register-user (role uint))
  (let ((user-info (get-user-info tx-sender)))
    (asserts! (not (get registered user-info)) ERR_ALREADY_REGISTERED)
    (asserts! (or (is-eq role RESEARCHER_ROLE) (is-eq role REVIEWER_ROLE)) ERR_UNAUTHORIZED)
    (map-set users
      { user: tx-sender }
      { role: role, reputation: u0, registered: true }
    )
    (ok true)
  )
)

(define-public (submit-paper (title (string-utf8 100)) (abstract (string-utf8 500)) (reward-amount uint))
  (let (
    (user-info (get-user-info tx-sender))
    (new-paper-id (+ (var-get paper-id-nonce) u1))
  )
    (asserts! (get registered user-info) ERR_NOT_REGISTERED)
    (asserts! (>= (ft-get-balance review-token tx-sender) reward-amount) ERR_INSUFFICIENT_BALANCE)
    (asserts! (> reward-amount u0) ERR_INVALID_AMOUNT)
    
    (try! (ft-burn? review-token reward-amount tx-sender))
    
    (var-set paper-id-nonce new-paper-id)
    (map-set papers
      { paper-id: new-paper-id }
      {
        author: tx-sender,
        title: title,
        abstract: abstract,
        reward-amount: reward-amount,
        status: "open",
        review-count: u0
      }
    )
    (ok new-paper-id)
  )
)

(define-public (submit-review (paper-id uint) (rating uint) (comment (string-utf8 500)))
  (let (
    (user-info (get-user-info tx-sender))
    (paper-info (unwrap! (get-paper paper-id) ERR_PAPER_NOT_FOUND))
    (current-review-count (get review-count paper-info))
  )
    (asserts! (get registered user-info) ERR_NOT_REGISTERED)
    (asserts! (not (is-eq tx-sender (get author paper-info))) ERR_SELF_REVIEW)
    (asserts! (is-none (get-review paper-id tx-sender)) ERR_ALREADY_REVIEWED)
    (asserts! (and (>= rating u1) (<= rating u5)) ERR_INVALID_AMOUNT)
    
    (map-set reviews
      { paper-id: paper-id, reviewer: tx-sender }
      {
        rating: rating,
        comment: comment,
        timestamp: stacks-block-height,
        rewarded: false
      }
    )
    
    (map-set papers
      { paper-id: paper-id }
      (merge paper-info { review-count: (+ current-review-count u1) })
    )
    
    (ok true)
  )
)

(define-public (distribute-rewards (paper-id uint) (reviewer principal))
  (let (
    (paper-info (unwrap! (get-paper paper-id) ERR_PAPER_NOT_FOUND))
    (review-info (unwrap! (get-review paper-id reviewer) ERR_REVIEW_NOT_FOUND))
    (reward-per-review (/ (get reward-amount paper-info) (get review-count paper-info)))
  )
    (asserts! (is-eq tx-sender (var-get admin)) ERR_UNAUTHORIZED)
    (asserts! (not (get rewarded review-info)) ERR_ALREADY_REVIEWED)
    
    (map-set reviews
      { paper-id: paper-id, reviewer: reviewer }
      (merge review-info { rewarded: true })
    )
    
    (try! (ft-mint? review-token reward-per-review reviewer))
    
    (ok reward-per-review)
  )
)

(define-public (update-reputation (user principal) (amount uint))
  (let ((user-info (get-user-info user)))
    (asserts! (is-eq tx-sender (var-get admin)) ERR_UNAUTHORIZED)
    
    (map-set users
      { user: user }
      (merge user-info { reputation: (+ (get reputation user-info) amount) })
    )
    
    (ok true)
  )
)

(define-public (mint-tokens (amount uint) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) ERR_UNAUTHORIZED)
    (try! (ft-mint? review-token amount recipient))
    (ok true)
  )
)

(define-public (transfer-tokens (amount uint) (recipient principal))
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (ft-transfer? review-token amount tx-sender recipient))
    (ok true)
  )
)

(define-public (close-paper (paper-id uint))
  (let ((paper-info (unwrap! (get-paper paper-id) ERR_PAPER_NOT_FOUND)))
    (asserts! (or 
      (is-eq tx-sender (get author paper-info))
      (is-eq tx-sender (var-get admin))
    ) ERR_UNAUTHORIZED)
    
    (map-set papers
      { paper-id: paper-id }
      (merge paper-info { status: "closed" })
    )
    
    (ok true)
  )
)