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


(define-constant ERR_BID_NOT_FOUND (err u400))
(define-constant ERR_BID_EXISTS (err u401))
(define-constant ERR_MARKETPLACE_CLOSED (err u402))
(define-constant ERR_INVALID_TIMELINE (err u403))
(define-constant ERR_BID_EXPIRED (err u404))
(define-constant ERR_INSUFFICIENT_BID (err u405))
(define-constant ERR_MARKETPLACE_NOT_FOUND (err u406))
(define-constant ERR_REVIEW_SLOT_TAKEN (err u407))
(define-constant ERR_INVALID_SELECTION (err u408))
(define-constant ERR_COMPLETION_OVERDUE (err u409))

(define-constant MARKETPLACE_DURATION u1000)
(define-constant MIN_BID_AMOUNT u10)
(define-constant MAX_REVIEW_SLOTS u5)
(define-constant COMPLETION_BUFFER u144)
(define-constant MARKETPLACE_FEE_PERCENT u5)

(define-map paper-marketplace
  { paper-id: uint }
  {
    author: principal,
    min-bid: uint,
    max-slots: uint,
    filled-slots: uint,
    deadline: uint,
    status: (string-ascii 20),
    total-bids: uint,
    created-at: uint
  }
)

(define-map reviewer-bids
  { paper-id: uint, reviewer: principal }
  {
    bid-amount: uint,
    proposed-timeline: uint,
    reviewer-message: (string-utf8 300),
    reviewer-reputation: uint,
    bid-timestamp: uint,
    status: (string-ascii 15),
    completion-deadline: uint
  }
)

(define-map marketplace-selections
  { paper-id: uint, slot: uint }
  {
    reviewer: principal,
    agreed-amount: uint,
    selection-timestamp: uint,
    completion-deadline: uint,
    completed: bool,
    payment-released: bool
  }
)

(define-map marketplace-escrow
  { paper-id: uint, reviewer: principal }
  { amount: uint, locked: bool }
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



;; (define-constant ERR_UNAUTHORIZED (err u100))
;; (define-constant ERR_REVIEW_NOT_FOUND (err u109))
;; (define-constant ERR_INVALID_AMOUNT (err u108))
(define-constant ERR_INSUFFICIENT_DATA (err u300))

(define-constant QUALITY_WEIGHT_DEPTH u30)
(define-constant QUALITY_WEIGHT_CONSISTENCY u25)
(define-constant QUALITY_WEIGHT_AUTHOR_RATING u25)
(define-constant QUALITY_WEIGHT_TIMELINESS u20)
(define-constant MAX_QUALITY_SCORE u100)
(define-constant MIN_REVIEWS_FOR_RANKING u5)

(define-map reviewer-quality-scores
  { reviewer: principal }
  {
    total-score: uint,
    review-count: uint,
    average-score: uint,
    depth-score: uint,
    consistency-score: uint,
    author-rating-score: uint,
    timeliness-score: uint,
    last-updated: uint
  }
)

(define-map review-quality-metrics
  { paper-id: uint, reviewer: principal }
  {
    depth-score: uint,
    word-count: uint,
    consistency-score: uint,
    timeliness-score: uint,
    quality-score: uint,
    calculated: bool
  }
)

(define-map reviewer-rankings
  { rank: uint }
  { reviewer: principal, score: uint }
)

(define-data-var total-ranked-reviewers uint u0)

(define-read-only (get-reviewer-quality-score (reviewer principal))
  (default-to
    {
      total-score: u0,
      review-count: u0,
      average-score: u0,
      depth-score: u0,
      consistency-score: u0,
      author-rating-score: u0,
      timeliness-score: u0,
      last-updated: u0
    }
    (map-get? reviewer-quality-scores { reviewer: reviewer })
  )
)

(define-read-only (get-review-quality-metrics (paper-id uint) (reviewer principal))
  (map-get? review-quality-metrics { paper-id: paper-id, reviewer: reviewer })
)

(define-read-only (get-reviewer-ranking (rank uint))
  (map-get? reviewer-rankings { rank: rank })
)



(define-private (calculate-depth-score (comment (string-utf8 500)))
  (let ((word-count (len comment)))
    (if (>= word-count u200)
      u100
      (if (>= word-count u100)
        u75
        (if (>= word-count u50)
          u50
          u25
        )
      )
    )
  )
)

(define-private (calculate-timeliness-score (review-timestamp uint) (paper-timestamp uint))
  (let ((time-diff (- review-timestamp paper-timestamp)))
    (if (<= time-diff u144)
      u100
      (if (<= time-diff u288)
        u75
        (if (<= time-diff u576)
          u50
          u25
        )
      )
    )
  )
)

(define-private (calculate-consistency-score (reviewer principal) (current-rating uint))
  (let (
    (quality-data (get-reviewer-quality-score reviewer))
    (review-count (get review-count quality-data))
  )
    (if (< review-count u3)
      u50
      (let ((avg-rating (/ (get total-score quality-data) review-count)))
        (if (<= (if (> current-rating avg-rating) (- current-rating avg-rating) (- avg-rating current-rating)) u1)
          u100
          (if (<= (if (> current-rating avg-rating) (- current-rating avg-rating) (- avg-rating current-rating)) u2)
            u75
            u50
          )
        )
      )
    )
  )
)


(define-public (update-reviewer-ranking (reviewer principal) (score uint))
  (let ((current-total (var-get total-ranked-reviewers)))
    (map-set reviewer-rankings
      { rank: (+ current-total u1) }
      { reviewer: reviewer, score: score }
    )
    (var-set total-ranked-reviewers (+ current-total u1))
    (ok true)
  )
)

(define-public (get-quality-bonus (reviewer principal))
  (let (
    (quality-data (get-reviewer-quality-score reviewer))
    (average-score (get average-score quality-data))
  )
    (if (>= average-score u90)
      (ok u150)
      (if (>= average-score u80)
        (ok u125)
        (if (>= average-score u70)
          (ok u110)
          (ok u100)
        )
      )
    )
  )
)

(define-public (distribute-quality-rewards (paper-id uint) (reviewer principal))
  (let (
    (quality-metrics (unwrap! (get-review-quality-metrics paper-id reviewer) ERR_REVIEW_NOT_FOUND))
    (quality-score (get quality-score quality-metrics))
    (base-reward u100)
    (bonus-multiplier (if (>= quality-score u90) u150
                      (if (>= quality-score u80) u125
                      (if (>= quality-score u70) u110 u100))))
    (final-reward (/ (* base-reward bonus-multiplier) u100))
  )
    (asserts! (get calculated quality-metrics) ERR_INSUFFICIENT_DATA)
    ;; (try! (contract-call? .review-incentive mint-tokens final-reward reviewer))
    (ok final-reward)
  )
)

(define-read-only (get-reviewer-stats (reviewer principal))
  (let ((quality-data (get-reviewer-quality-score reviewer)))
    (ok {
      average-quality: (get average-score quality-data),
      total-reviews: (get review-count quality-data),
      ranking-eligible: (>= (get review-count quality-data) MIN_REVIEWS_FOR_RANKING)
    })
  )
)


(define-data-var marketplace-fee-collector principal tx-sender)

(define-read-only (get-marketplace-info (paper-id uint))
  (map-get? paper-marketplace { paper-id: paper-id })
)

(define-read-only (get-reviewer-bid (paper-id uint) (reviewer principal))
  (map-get? reviewer-bids { paper-id: paper-id, reviewer: reviewer })
)

(define-read-only (get-marketplace-selection (paper-id uint) (slot uint))
  (map-get? marketplace-selections { paper-id: paper-id, slot: slot })
)

(define-read-only (get-escrow-amount (paper-id uint) (reviewer principal))
  (default-to { amount: u0, locked: false }
    (map-get? marketplace-escrow { paper-id: paper-id, reviewer: reviewer })
  )
)

(define-public (create-review-marketplace (paper-id uint) (min-bid uint) (max-slots uint) (duration uint))
  (let (
    (paper-info (unwrap! (get-paper paper-id) ERR_PAPER_NOT_FOUND))
    (marketplace-deadline (+ stacks-block-height duration))
  )
    (asserts! (is-eq tx-sender (get author paper-info)) ERR_UNAUTHORIZED)
    (asserts! (is-none (get-marketplace-info paper-id)) ERR_MARKETPLACE_CLOSED)
    (asserts! (>= min-bid MIN_BID_AMOUNT) ERR_INSUFFICIENT_BID)
    (asserts! (and (> max-slots u0) (<= max-slots MAX_REVIEW_SLOTS)) ERR_INVALID_AMOUNT)
    (asserts! (and (> duration u0) (<= duration MARKETPLACE_DURATION)) ERR_INVALID_TIMELINE)
    
    (map-set paper-marketplace
      { paper-id: paper-id }
      {
        author: tx-sender,
        min-bid: min-bid,
        max-slots: max-slots,
        filled-slots: u0,
        deadline: marketplace-deadline,
        status: "open",
        total-bids: u0,
        created-at: stacks-block-height
      }
    )
    
    (ok true)
  )
)

(define-public (place-review-bid (paper-id uint) (bid-amount uint) (proposed-timeline uint) (reviewer-message (string-utf8 300)))
  (let (
    (marketplace-info (unwrap! (get-marketplace-info paper-id) ERR_MARKETPLACE_NOT_FOUND))
    (paper-info (unwrap! (get-paper paper-id) ERR_PAPER_NOT_FOUND))
    (user-info (get-user-info tx-sender))
    (completion-deadline (+ stacks-block-height proposed-timeline))
  )
    (asserts! (get registered user-info) ERR_NOT_REGISTERED)
    (asserts! (not (is-eq tx-sender (get author paper-info))) ERR_SELF_REVIEW)
    (asserts! (is-none (get-reviewer-bid paper-id tx-sender)) ERR_BID_EXISTS)
    (asserts! (is-eq (get status marketplace-info) "open") ERR_MARKETPLACE_CLOSED)
    (asserts! (< stacks-block-height (get deadline marketplace-info)) ERR_BID_EXPIRED)
    (asserts! (>= bid-amount (get min-bid marketplace-info)) ERR_INSUFFICIENT_BID)
    (asserts! (and (> proposed-timeline u0) (<= proposed-timeline u1000)) ERR_INVALID_TIMELINE)
    (asserts! (>= (ft-get-balance review-token tx-sender) bid-amount) ERR_INSUFFICIENT_BALANCE)
    
    (try! (ft-burn? review-token bid-amount tx-sender))
    
    (map-set reviewer-bids
      { paper-id: paper-id, reviewer: tx-sender }
      {
        bid-amount: bid-amount,
        proposed-timeline: proposed-timeline,
        reviewer-message: reviewer-message,
        reviewer-reputation: (get reputation user-info),
        bid-timestamp: stacks-block-height,
        status: "pending",
        completion-deadline: completion-deadline
      }
    )
    
    (map-set marketplace-escrow
      { paper-id: paper-id, reviewer: tx-sender }
      { amount: bid-amount, locked: true }
    )
    
    (map-set paper-marketplace
      { paper-id: paper-id }
      (merge marketplace-info { total-bids: (+ (get total-bids marketplace-info) u1) })
    )
    
    (ok true)
  )
)

(define-public (select-reviewer (paper-id uint) (reviewer principal) (slot uint))
  (let (
    (marketplace-info (unwrap! (get-marketplace-info paper-id) ERR_MARKETPLACE_NOT_FOUND))
    (bid-info (unwrap! (get-reviewer-bid paper-id reviewer) ERR_BID_NOT_FOUND))
    (paper-info (unwrap! (get-paper paper-id) ERR_PAPER_NOT_FOUND))
  )
    (asserts! (is-eq tx-sender (get author paper-info)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status marketplace-info) "open") ERR_MARKETPLACE_CLOSED)
    (asserts! (is-eq (get status bid-info) "pending") ERR_INVALID_SELECTION)
    (asserts! (and (> slot u0) (<= slot (get max-slots marketplace-info))) ERR_INVALID_AMOUNT)
    (asserts! (is-none (get-marketplace-selection paper-id slot)) ERR_REVIEW_SLOT_TAKEN)
    (asserts! (< (get filled-slots marketplace-info) (get max-slots marketplace-info)) ERR_REVIEW_SLOT_TAKEN)
    
    (map-set marketplace-selections
      { paper-id: paper-id, slot: slot }
      {
        reviewer: reviewer,
        agreed-amount: (get bid-amount bid-info),
        selection-timestamp: stacks-block-height,
        completion-deadline: (get completion-deadline bid-info),
        completed: false,
        payment-released: false
      }
    )
    
    (map-set reviewer-bids
      { paper-id: paper-id, reviewer: reviewer }
      (merge bid-info { status: "accepted" })
    )
    
    (let ((updated-filled-slots (+ (get filled-slots marketplace-info) u1)))
      (map-set paper-marketplace
        { paper-id: paper-id }
        (merge marketplace-info { 
          filled-slots: updated-filled-slots,
          status: (if (>= updated-filled-slots (get max-slots marketplace-info)) "filled" "open")
        })
      )
    )
    
    (ok true)
  )
)

(define-public (complete-marketplace-review (paper-id uint) (reviewer principal) (rating uint) (comment (string-utf8 500)))
  (let (
    (marketplace-info (unwrap! (get-marketplace-info paper-id) ERR_MARKETPLACE_NOT_FOUND))
    (paper-info (unwrap! (get-paper paper-id) ERR_PAPER_NOT_FOUND))
    (user-info (get-user-info tx-sender))
  )
    (asserts! (get registered user-info) ERR_NOT_REGISTERED)
    (asserts! (is-eq tx-sender reviewer) ERR_UNAUTHORIZED)
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
    
    (let ((current-review-count (get review-count paper-info)))
      (map-set papers
        { paper-id: paper-id }
        (merge paper-info { review-count: (+ current-review-count u1) })
      )
    )
    
    (ok true)
  )
)

(define-public (release-marketplace-payment (paper-id uint) (reviewer principal) (slot uint))
  (let (
    (marketplace-info (unwrap! (get-marketplace-info paper-id) ERR_MARKETPLACE_NOT_FOUND))
    (selection-info (unwrap! (get-marketplace-selection paper-id slot) ERR_INVALID_SELECTION))
    (paper-info (unwrap! (get-paper paper-id) ERR_PAPER_NOT_FOUND))
    (escrow-info (get-escrow-amount paper-id reviewer))
    (review-info (get-review paper-id reviewer))
  )
    (asserts! (is-eq tx-sender (get author paper-info)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get reviewer selection-info) reviewer) ERR_INVALID_SELECTION)
    (asserts! (is-some review-info) ERR_REVIEW_NOT_FOUND)
    (asserts! (not (get payment-released selection-info)) ERR_ALREADY_REVIEWED)
    (asserts! (get locked escrow-info) ERR_INVALID_AMOUNT)
    
    (let (
      (payment-amount (get agreed-amount selection-info))
      (marketplace-fee (/ (* payment-amount MARKETPLACE_FEE_PERCENT) u100))
      (reviewer-payment (- payment-amount marketplace-fee))
    )
      (map-set marketplace-selections
        { paper-id: paper-id, slot: slot }
        (merge selection-info { payment-released: true, completed: true })
      )
      
      (map-set marketplace-escrow
        { paper-id: paper-id, reviewer: reviewer }
        { amount: u0, locked: false }
      )
      
      (try! (ft-mint? review-token reviewer-payment reviewer))
      (try! (ft-mint? review-token marketplace-fee (var-get marketplace-fee-collector)))
      
      (ok reviewer-payment)
    )
  )
)

(define-public (withdraw-expired-bid (paper-id uint) (reviewer principal))
  (let (
    (marketplace-info (unwrap! (get-marketplace-info paper-id) ERR_MARKETPLACE_NOT_FOUND))
    (bid-info (unwrap! (get-reviewer-bid paper-id reviewer) ERR_BID_NOT_FOUND))
    (escrow-info (get-escrow-amount paper-id reviewer))
  )
    (asserts! (is-eq tx-sender reviewer) ERR_UNAUTHORIZED)
    (asserts! (>= stacks-block-height (get deadline marketplace-info)) ERR_BID_EXPIRED)
    (asserts! (is-eq (get status bid-info) "pending") ERR_INVALID_SELECTION)
    (asserts! (get locked escrow-info) ERR_INVALID_AMOUNT)
    
    (map-set reviewer-bids
      { paper-id: paper-id, reviewer: reviewer }
      (merge bid-info { status: "withdrawn" })
    )
    
    (map-set marketplace-escrow
      { paper-id: paper-id, reviewer: reviewer }
      { amount: u0, locked: false }
    )
    
    (try! (ft-mint? review-token (get amount escrow-info) reviewer))
    
    (ok true)
  )
)

(define-public (claim-overdue-payment (paper-id uint) (reviewer principal) (slot uint))
  (let (
    (selection-info (unwrap! (get-marketplace-selection paper-id slot) ERR_INVALID_SELECTION))
    (escrow-info (get-escrow-amount paper-id reviewer))
    (review-info (get-review paper-id reviewer))
  )
    (asserts! (is-eq tx-sender reviewer) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get reviewer selection-info) reviewer) ERR_INVALID_SELECTION)
    (asserts! (is-some review-info) ERR_REVIEW_NOT_FOUND)
    (asserts! (not (get payment-released selection-info)) ERR_ALREADY_REVIEWED)
    (asserts! (>= stacks-block-height (+ (get completion-deadline selection-info) COMPLETION_BUFFER)) ERR_COMPLETION_OVERDUE)
    (asserts! (get locked escrow-info) ERR_INVALID_AMOUNT)
    
    (let (
      (payment-amount (get agreed-amount selection-info))
      (marketplace-fee (/ (* payment-amount MARKETPLACE_FEE_PERCENT) u100))
      (reviewer-payment (- payment-amount marketplace-fee))
    )
      (map-set marketplace-selections
        { paper-id: paper-id, slot: slot }
        (merge selection-info { payment-released: true, completed: true })
      )
      
      (map-set marketplace-escrow
        { paper-id: paper-id, reviewer: reviewer }
        { amount: u0, locked: false }
      )
      
      (try! (ft-mint? review-token reviewer-payment reviewer))
      (try! (ft-mint? review-token marketplace-fee (var-get marketplace-fee-collector)))
      
      (ok reviewer-payment)
    )
  )
)

(define-public (get-marketplace-stats (paper-id uint))
  (let ((marketplace-info (unwrap! (get-marketplace-info paper-id) ERR_MARKETPLACE_NOT_FOUND)))
    (ok {
      total-bids: (get total-bids marketplace-info),
      filled-slots: (get filled-slots marketplace-info),
      max-slots: (get max-slots marketplace-info),
      min-bid: (get min-bid marketplace-info),
      status: (get status marketplace-info),
      deadline: (get deadline marketplace-info)
    })
  )
)

(define-public (get-active-marketplace-bids (paper-id uint))
  (let ((marketplace-info (unwrap! (get-marketplace-info paper-id) ERR_MARKETPLACE_NOT_FOUND)))
    (ok {
      paper-id: paper-id,
      total-bids: (get total-bids marketplace-info),
      available-slots: (- (get max-slots marketplace-info) (get filled-slots marketplace-info)),
      deadline: (get deadline marketplace-info)
    })
  )
)

(define-public (set-marketplace-fee-collector (new-collector principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) ERR_UNAUTHORIZED)
    (var-set marketplace-fee-collector new-collector)
    (ok true)
  )
)

;; Citation Network and Impact Scoring System
(define-constant ERR_CITATION_EXISTS (err u500))
(define-constant ERR_CITATION_NOT_FOUND (err u501))
(define-constant ERR_INVALID_CITATION (err u502))
(define-constant ERR_SELF_CITATION (err u503))
(define-constant ERR_CITATION_LIMIT_EXCEEDED (err u504))
(define-constant ERR_IMPACT_NOT_CALCULATED (err u505))

;; Constants for citation system
(define-constant MAX_CITATIONS_PER_PAPER u20)
(define-constant CITATION_REWARD_BASE u25)
(define-constant IMPACT_CALCULATION_THRESHOLD u3)
(define-constant CITATION_VERIFICATION_PERIOD u100)
(define-constant NETWORK_EFFECT_MULTIPLIER u150)

;; Track citations between papers
(define-map paper-citations
  { citing-paper: uint, cited-paper: uint }
  {
    citation-context: (string-utf8 200),
    verified: bool,
    timestamp: uint,
    citation-type: (string-ascii 15),
    relevance-score: uint
  }
)

;; Track total citations for each paper
(define-map paper-citation-counts
  { paper-id: uint }
  {
    total-citations: uint,
    verified-citations: uint,
    h-index: uint,
    impact-score: uint,
    last-calculated: uint,
    citation-reward-pool: uint
  }
)

;; Track author citation networks
(define-map author-citation-metrics
  { author: principal }
  {
    total-citations-received: uint,
    total-citations-made: uint,
    network-reputation: uint,
    avg-impact-score: uint,
    active-papers: uint,
    last-updated: uint
  }
)

;; Track citation verification by reviewers
(define-map citation-verifications
  { citing-paper: uint, cited-paper: uint, verifier: principal }
  {
    verified: bool,
    verification-timestamp: uint,
    verifier-reputation: uint
  }
)

;; Store citation reward distributions
(define-map citation-rewards
  { paper-id: uint, reward-period: uint }
  {
    total-rewards: uint,
    distributed: bool,
    beneficiaries: uint,
    reward-per-citation: uint
  }
)

(define-data-var citation-reward-pool uint u0)
(define-data-var total-network-citations uint u0)

;; Read-only functions for citation data
(define-read-only (get-citation-info (citing-paper uint) (cited-paper uint))
  (map-get? paper-citations { citing-paper: citing-paper, cited-paper: cited-paper })
)

(define-read-only (get-paper-citation-stats (paper-id uint))
  (default-to
    {
      total-citations: u0,
      verified-citations: u0,
      h-index: u0,
      impact-score: u0,
      last-calculated: u0,
      citation-reward-pool: u0
    }
    (map-get? paper-citation-counts { paper-id: paper-id })
  )
)

(define-read-only (get-author-citation-metrics (author principal))
  (default-to
    {
      total-citations-received: u0,
      total-citations-made: u0,
      network-reputation: u0,
      avg-impact-score: u0,
      active-papers: u0,
      last-updated: u0
    }
    (map-get? author-citation-metrics { author: author })
  )
)

;; Submit a citation when publishing a new paper
(define-public (add-paper-citation (citing-paper uint) (cited-paper uint) (citation-context (string-utf8 200)) (citation-type (string-ascii 15)))
  (let (
    (citing-paper-info (unwrap! (get-paper citing-paper) ERR_PAPER_NOT_FOUND))
    (cited-paper-info (unwrap! (get-paper cited-paper) ERR_PAPER_NOT_FOUND))
    (citing-author (get author citing-paper-info))
    (cited-author (get author cited-paper-info))
    (existing-citation (get-citation-info citing-paper cited-paper))
  )
    ;; Verify citation is valid
    (asserts! (is-eq tx-sender citing-author) ERR_UNAUTHORIZED)
    (asserts! (not (is-eq citing-paper cited-paper)) ERR_SELF_CITATION)
    (asserts! (not (is-eq citing-author cited-author)) ERR_SELF_CITATION)
    (asserts! (is-none existing-citation) ERR_CITATION_EXISTS)
    
    ;; Check citation limits
    (let ((current-citations (count-paper-citations citing-paper)))
      (asserts! (< current-citations MAX_CITATIONS_PER_PAPER) ERR_CITATION_LIMIT_EXCEEDED)
    )
    
    ;; Record the citation
    (map-set paper-citations
      { citing-paper: citing-paper, cited-paper: cited-paper }
      {
        citation-context: citation-context,
        verified: false,
        timestamp: stacks-block-height,
        citation-type: citation-type,
        relevance-score: u0
      }
    )
    
    ;; Update citation counts
    (update-citation-counts cited-paper)
    (update-author-metrics citing-author cited-author)
    (var-set total-network-citations (+ (var-get total-network-citations) u1))
    
    (ok true)
  )
)

;; Verify a citation (called by qualified reviewers)
(define-public (verify-citation (citing-paper uint) (cited-paper uint) (relevance-score uint))
  (let (
    (citation-info (unwrap! (get-citation-info citing-paper cited-paper) ERR_CITATION_NOT_FOUND))
    (verifier-info (get-user-info tx-sender))
    (existing-verification (map-get? citation-verifications { citing-paper: citing-paper, cited-paper: cited-paper, verifier: tx-sender }))
  )
    ;; Check verifier qualifications
    (asserts! (get registered verifier-info) ERR_NOT_REGISTERED)
    (asserts! (>= (get reputation verifier-info) u50) ERR_UNAUTHORIZED)
    (asserts! (is-none existing-verification) ERR_ALREADY_REVIEWED)
    (asserts! (and (>= relevance-score u1) (<= relevance-score u10)) ERR_INVALID_AMOUNT)
    
    ;; Record verification
    (map-set citation-verifications
      { citing-paper: citing-paper, cited-paper: cited-paper, verifier: tx-sender }
      {
        verified: true,
        verification-timestamp: stacks-block-height,
        verifier-reputation: (get reputation verifier-info)
      }
    )
    
    ;; Update citation with verification
    (map-set paper-citations
      { citing-paper: citing-paper, cited-paper: cited-paper }
      (merge citation-info { 
        verified: true,
        relevance-score: relevance-score
      })
    )
    
    ;; Update verified citation count
    (let ((citation-stats (get-paper-citation-stats cited-paper)))
      (map-set paper-citation-counts
        { paper-id: cited-paper }
        (merge citation-stats { 
          verified-citations: (+ (get verified-citations citation-stats) u1)
        })
      )
    )
    
    (ok true)
  )
)

;; Calculate impact score for a paper
(define-public (calculate-impact-score (paper-id uint))
  (let (
    (citation-stats (get-paper-citation-stats paper-id))
    (paper-info (unwrap! (get-paper paper-id) ERR_PAPER_NOT_FOUND))
    (total-citations (get total-citations citation-stats))
    (verified-citations (get verified-citations citation-stats))
  )
    ;; Require minimum citations for calculation
    (asserts! (>= total-citations IMPACT_CALCULATION_THRESHOLD) ERR_IMPACT_NOT_CALCULATED)
    
    (let (
      ;; Calculate weighted impact score
      (base-score (* total-citations u10))
      (verification-bonus (* verified-citations u15))
      (network-effect (/ (* total-citations (var-get total-network-citations)) u100))
      (age-factor (if (> paper-id u50) u80 u100))
      (final-impact (/ (* (+ base-score verification-bonus network-effect) age-factor) u100))
    )
      ;; Update impact score
      (map-set paper-citation-counts
        { paper-id: paper-id }
        (merge citation-stats {
          impact-score: final-impact,
          last-calculated: stacks-block-height
        })
      )
      
      ;; Update author metrics
      (update-author-impact-metrics (get author paper-info) final-impact)
      
      (ok final-impact)
    )
  )
)

;; Distribute citation rewards to highly cited papers
(define-public (distribute-citation-rewards (paper-id uint))
  (let (
    (citation-stats (get-paper-citation-stats paper-id))
    (paper-info (unwrap! (get-paper paper-id) ERR_PAPER_NOT_FOUND))
    (impact-score (get impact-score citation-stats))
    (verified-citations (get verified-citations citation-stats))
  )
    ;; Check eligibility for rewards
    (asserts! (> impact-score u50) ERR_IMPACT_NOT_CALCULATED)
    (asserts! (>= verified-citations u3) ERR_INSUFFICIENT_DATA)
    
    (let (
      ;; Calculate reward based on impact and citations
      (base-reward CITATION_REWARD_BASE)
      (impact-multiplier (/ impact-score u10))
      (citation-bonus (* verified-citations u5))
      (total-reward (+ base-reward impact-multiplier citation-bonus))
    )
      ;; Distribute rewards to paper author
      (try! (ft-mint? review-token total-reward (get author paper-info)))
      
      ;; Update citation reward pool
      (map-set paper-citation-counts
        { paper-id: paper-id }
        (merge citation-stats {
          citation-reward-pool: (+ (get citation-reward-pool citation-stats) total-reward)
        })
      )
      
      (ok total-reward)
    )
  )
)

;; Helper function to count citations for a paper
(define-private (count-paper-citations (paper-id uint))
  (get total-citations (get-paper-citation-stats paper-id))
)

;; Helper function to update citation counts
(define-private (update-citation-counts (paper-id uint))
  (let ((current-stats (get-paper-citation-stats paper-id)))
    (map-set paper-citation-counts
      { paper-id: paper-id }
      (merge current-stats {
        total-citations: (+ (get total-citations current-stats) u1)
      })
    )
    true
  )
)

;; Helper function to update author citation metrics
(define-private (update-author-metrics (citing-author principal) (cited-author principal))
  (begin
    ;; Update citing author stats
    (let ((citing-metrics (get-author-citation-metrics citing-author)))
      (map-set author-citation-metrics
        { author: citing-author }
        (merge citing-metrics {
          total-citations-made: (+ (get total-citations-made citing-metrics) u1),
          last-updated: stacks-block-height
        })
      )
    )
    
    ;; Update cited author stats
    (let ((cited-metrics (get-author-citation-metrics cited-author)))
      (map-set author-citation-metrics
        { author: cited-author }
        (merge cited-metrics {
          total-citations-received: (+ (get total-citations-received cited-metrics) u1),
          last-updated: stacks-block-height
        })
      )
    )
    true
  )
)

;; Helper function to update author impact metrics
(define-private (update-author-impact-metrics (author principal) (new-impact uint))
  (let ((current-metrics (get-author-citation-metrics author)))
    (let (
      (current-papers (get active-papers current-metrics))
      (current-avg (get avg-impact-score current-metrics))
      (new-avg (if (> current-papers u0)
                 (/ (+ (* current-avg current-papers) new-impact) (+ current-papers u1))
                 new-impact))
    )
      (map-set author-citation-metrics
        { author: author }
        (merge current-metrics {
          avg-impact-score: new-avg,
          active-papers: (+ current-papers u1),
          last-updated: stacks-block-height
        })
      )
    )
    true
  )
)

;; Get citation network statistics
(define-read-only (get-network-stats)
  (ok {
    total-citations: (var-get total-network-citations),
    reward-pool: (var-get citation-reward-pool),
    active-papers: (var-get paper-id-nonce)
  })
)

;; Check if author qualifies for citation bonus
(define-public (get-citation-reputation-bonus (author principal))
  (let ((metrics (get-author-citation-metrics author)))
    (let (
      (citations-received (get total-citations-received metrics))
      (avg-impact (get avg-impact-score metrics))
    )
      (if (and (>= citations-received u10) (>= avg-impact u75))
        (ok u200)  ;; 200% reputation multiplier for highly cited authors
        (if (and (>= citations-received u5) (>= avg-impact u50))
          (ok u150)  ;; 150% multiplier for moderately cited authors
          (ok u100)  ;; Standard multiplier
        )
      )
    )
  )
)
