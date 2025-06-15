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




(define-constant ERR_DISPUTE_EXISTS (err u200))
(define-constant ERR_DISPUTE_NOT_FOUND (err u201))
(define-constant ERR_ALREADY_VOTED (err u202))
(define-constant ERR_DISPUTE_CLOSED (err u203))
(define-constant ERR_NOT_ARBITRATOR (err u204))
(define-constant ERR_INSUFFICIENT_STAKE (err u205))

(define-constant DISPUTE_STAKE_AMOUNT u50)
(define-constant ARBITRATOR_ROLE u4)
(define-constant MIN_ARBITRATORS u3)

(define-map disputes
  { dispute-id: uint }
  {
    paper-id: uint,
    reviewer: principal,
    author: principal,
    reason: (string-utf8 200),
    status: (string-ascii 10),
    votes-for: uint,
    votes-against: uint,
    total-votes: uint,
    stake-amount: uint,
    created-at: uint
  }
)

(define-map arbitrator-votes
  { dispute-id: uint, arbitrator: principal }
  { vote: bool, timestamp: uint }
)

(define-map arbitrators
  { arbitrator: principal }
  { active: bool, cases-resolved: uint }
)

(define-data-var dispute-id-nonce uint u0)
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
    review-count: uint,
    current-version: uint
  }
)

(define-map reviews
  { paper-id: uint, reviewer: principal }
  {
    rating: uint,
    comment: (string-utf8 500),
    timestamp: uint,
    rewarded: bool,
    author-rating: (optional uint),
    staked: uint
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
        review-count: u0,
        current-version: u1
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
        rewarded: false,
        author-rating: none,
        staked: u0
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



(define-constant ERR_VERSION_NOT_FOUND (err u110))

(define-map paper-versions
  { paper-id: uint, version: uint }
  {
    title: (string-utf8 100),
    abstract: (string-utf8 500),
    timestamp: uint
  }
)

(define-map paper
  { paper-id: uint }
  {
    author: principal,
    title: (string-utf8 100),
    abstract: (string-utf8 500),
    reward-amount: uint,
    status: (string-ascii 20),
    review-count: uint,
    current-version: uint
  }
)

(define-public (update-paper (paper-id uint) (new-title (string-utf8 100)) (new-abstract (string-utf8 500)))
  (let (
    (paper-info (unwrap! (get-paper paper-id) ERR_PAPER_NOT_FOUND))
    (current-version (get current-version paper-info))
    (next-version (+ current-version u1))
  )
    (asserts! (is-eq tx-sender (get author paper-info)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status paper-info) "open") ERR_UNAUTHORIZED)
    
    (map-set paper-versions
      { paper-id: paper-id, version: next-version }
      {
        title: new-title,
        abstract: new-abstract,
        timestamp: stacks-block-height
      }
    )
    
    (map-set papers
      { paper-id: paper-id }
      (merge paper-info { 
        title: new-title,
        abstract: new-abstract,
        current-version: next-version
      })
    )
    
    (ok next-version)
  )
)

(define-read-only (get-paper-version (paper-id uint) (version uint))
  (map-get? paper-versions { paper-id: paper-id, version: version })
)


(define-constant REVIEW_STAKE_AMOUNT u100)
(define-constant MIN_ACCEPTABLE_RATING u3)
(define-constant ERR_REVIEW_ALREADY_RATED (err u111))

(define-map review
  { paper-id: uint, reviewer: principal }
  {
    rating: uint,
    comment: (string-utf8 500),
    timestamp: uint,
    rewarded: bool,
    author-rating: (optional uint),
    staked: uint
  }
)

(define-public (submit-review-with-stake (paper-id uint) (rating uint) (comment (string-utf8 500)))
  (let (
    (user-info (get-user-info tx-sender))
    (paper-info (unwrap! (get-paper paper-id) ERR_PAPER_NOT_FOUND))
  )
    (asserts! (get registered user-info) ERR_NOT_REGISTERED)
    (asserts! (not (is-eq tx-sender (get author paper-info))) ERR_SELF_REVIEW)
    (asserts! (is-none (get-review paper-id tx-sender)) ERR_ALREADY_REVIEWED)
    (asserts! (and (>= rating u1) (<= rating u5)) ERR_INVALID_AMOUNT)
    (asserts! (>= (ft-get-balance review-token tx-sender) REVIEW_STAKE_AMOUNT) ERR_INSUFFICIENT_BALANCE)
    
    (try! (ft-burn? review-token REVIEW_STAKE_AMOUNT tx-sender))
    
    (map-set review
      { paper-id: paper-id, reviewer: tx-sender }
      {
        rating: rating,
        comment: comment,
        timestamp: stacks-block-height,
        rewarded: false,
        author-rating: none,
        staked: REVIEW_STAKE_AMOUNT
      }
    )
    
    (ok true)
  )
)

(define-public (rate-review (paper-id uint) (reviewer principal) (author-rating uint))
  (let (
    (paper-info (unwrap! (get-paper paper-id) ERR_PAPER_NOT_FOUND))
    (review-info (unwrap! (get-review paper-id reviewer) ERR_REVIEW_NOT_FOUND))
  )
    (asserts! (is-eq tx-sender (get author paper-info)) ERR_UNAUTHORIZED)
    (asserts! (is-none (get author-rating review-info)) ERR_REVIEW_ALREADY_RATED)
    (asserts! (and (>= author-rating u1) (<= author-rating u5)) ERR_INVALID_AMOUNT)
    
    (map-set reviews
      { paper-id: paper-id, reviewer: reviewer }
      (merge review-info { author-rating: (some author-rating) })
    )
    
    (if (>= author-rating MIN_ACCEPTABLE_RATING)
      (try! (ft-mint? review-token (get staked review-info) reviewer))
      true
    )
    
    (ok author-rating)
  )
)


(define-public (get-review-stake (paper-id uint) (reviewer principal))
  (let ((review-info (unwrap! (get-review paper-id reviewer) ERR_REVIEW_NOT_FOUND)))
    (ok (get staked review-info))
  )
)
(define-public (withdraw-review-stake (paper-id uint) (reviewer principal))
  (let (
    (review-info (unwrap! (get-review paper-id reviewer) ERR_REVIEW_NOT_FOUND))
    (stake-amount (get staked review-info))
  )
    (asserts! (is-eq tx-sender reviewer) ERR_UNAUTHORIZED)
    (asserts! (> stake-amount u0) ERR_INVALID_AMOUNT)
    
    (map-set reviews
      { paper-id: paper-id, reviewer: reviewer }
      (merge review-info { staked: u0 })
    )
    
    (try! (ft-mint? review-token stake-amount reviewer))
    
    (ok true)
  )
)
(define-public (get-reviewer-reputation (reviewer principal))
  (let ((user-info (get-user-info reviewer)))
    (ok (get reputation user-info))
  )
)



(define-read-only (get-dispute (dispute-id uint))
  (map-get? disputes { dispute-id: dispute-id })
)

(define-read-only (is-arbitrator (user principal))
  (default-to false (get active (map-get? arbitrators { arbitrator: user })))
)



(define-public (create-dispute (paper-id uint) (reviewer principal) (reason (string-utf8 200)))
  (let (
    (paper-info (unwrap! (get-paper paper-id) ERR_PAPER_NOT_FOUND))
    (new-dispute-id (+ (var-get dispute-id-nonce) u1))
  )
    (asserts! (is-eq tx-sender reviewer) ERR_UNAUTHORIZED)
    (asserts! (is-none (map-get? disputes { dispute-id: new-dispute-id })) ERR_DISPUTE_EXISTS)
    
    (var-set dispute-id-nonce new-dispute-id)
    (map-set disputes
      { dispute-id: new-dispute-id }
      {
        paper-id: paper-id,
        reviewer: reviewer,
        author: (get author paper-info),
        reason: reason,
        status: "open",
        votes-for: u0,
        votes-against: u0,
        total-votes: u0,
        stake-amount: DISPUTE_STAKE_AMOUNT,
        created-at: stacks-block-height
      }
    )
    (ok new-dispute-id)
  )
)


(define-read-only (get-dispute-status (dispute-id uint))
  (let ((dispute-info (get-dispute dispute-id)))
    (match dispute-info
      dispute (ok {
        status: (get status dispute),
        votes-for: (get votes-for dispute),
        votes-against: (get votes-against dispute),
        total-votes: (get total-votes dispute)
      })
      ERR_DISPUTE_NOT_FOUND
    )
  )
)

(define-read-only (get-arbitrator-vote (dispute-id uint) (arbitrator principal))
  (map-get? arbitrator-votes { dispute-id: dispute-id, arbitrator: arbitrator })
)