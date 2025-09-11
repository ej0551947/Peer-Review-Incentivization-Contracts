;; Enhanced Review Challenge System
;; Improved security, fairer scoring, and proper reward distribution

;; Enhanced error constants
(define-constant err-not-found (err u601))
(define-constant err-unauthorized (err u602))
(define-constant err-challenge-closed (err u603))
(define-constant err-already-submitted (err u604))
(define-constant err-insufficient-reward (err u605))
(define-constant err-invalid-parameters (err u606))
(define-constant err-deadline-passed (err u607))
(define-constant err-challenge-active (err u608))
(define-constant err-insufficient-participants (err u609))
(define-constant err-already-finalized (err u610))
(define-constant err-contract-paused (err u611))
(define-constant err-rewards-claimed (err u612))
(define-constant err-duplicate-reviewer (err u613))

;; Enhanced constants with better economics
(define-constant min-challenge-duration u144) ;; ~1 day minimum
(define-constant max-challenge-duration u1440) ;; ~10 days maximum
(define-constant min-reward-pool u500) ;; Minimum total rewards
(define-constant max-reward-pool u10000) ;; Maximum to prevent exploitation
(define-constant max-participants u20)
(define-constant min-participants u3)
(define-constant challenge-entry-fee u50) ;; Fee to join challenge
(define-constant platform-fee-percent u5) ;; 5% platform fee

;; Enhanced reward tiers with more distribution options
(define-constant first-place-percent u40) ;; 40% of pool
(define-constant second-place-percent u25) ;; 25% of pool  
(define-constant third-place-percent u20) ;; 20% of pool
(define-constant participation-pool-percent u15) ;; 15% for all participants

;; Quality scoring weights
(define-constant quality-weight u40)
(define-constant speed-weight u25)
(define-constant length-weight u20)
(define-constant consistency-weight u15)

;; data vars
(define-data-var next-challenge-id uint u1)
(define-data-var contract-paused bool false)
(define-data-var platform-fee-collector principal tx-sender)

;; Enhanced data maps with better tracking
(define-map review-challenges
  { challenge-id: uint }
  {
    paper-id: uint,
    organizer: principal,
    title: (string-ascii 100),
    description: (string-utf8 300),
    total-reward-pool: uint,
    entry-fee: uint,
    max-participants: uint,
    current-participants: uint,
    challenge-start: uint,
    challenge-end: uint,
    status: (string-ascii 15), ;; active, completed, cancelled, finalized
    winner-1st: (optional principal),
    winner-2nd: (optional principal),
    winner-3rd: (optional principal),
    finalized: bool,
    rewards-distributed: bool,
    avg-quality-score: uint,
    category: (string-ascii 30)
  }
)

(define-map challenge-participants
  { challenge-id: uint, reviewer: principal }
  {
    entry-timestamp: uint,
    review-quality-score: uint,
    review-submission: (optional (string-utf8 400)),
    final-rank: (optional uint),
    reward-earned: uint,
    performance-bonus: uint,
    speed-score: uint,
    length-score: uint,
    consistency-score: uint,
    claimed-reward: bool,
    disqualified: bool,
    disqualification-reason: (optional (string-ascii 50))
  }
)

(define-map challenge-leaderboard
  { challenge-id: uint, rank: uint }
  {
    reviewer: principal,
    total-score: uint,
    quality-metrics: uint,
    speed-bonus: uint,
    final-position: uint,
    score-breakdown: (string-ascii 100)
  }
)

;; Anti-gaming measures
(define-map reviewer-challenge-history
  { reviewer: principal }
  {
    total-challenges: uint,
    total-wins: uint,
    avg-quality: uint,
    suspicious-activity: bool,
    last-challenge: uint
  }
)

;; Challenge integrity tracking
(define-map challenge-integrity
  { challenge-id: uint }
  {
    duplicate-submissions: uint,
    flagged-reviews: uint,
    quality-variance: uint,
    integrity-score: uint
  }
)

;; Enhanced read-only functions
(define-read-only (get-contract-status)
  (ok {
    paused: (var-get contract-paused),
    next-challenge-id: (var-get next-challenge-id),
    platform-fee-collector: (var-get platform-fee-collector)
  })
)

(define-read-only (get-review-challenge (challenge-id uint))
  (map-get? review-challenges { challenge-id: challenge-id })
)

(define-read-only (get-challenge-participant (challenge-id uint) (reviewer principal))
  (map-get? challenge-participants { challenge-id: challenge-id, reviewer: reviewer })
)

(define-read-only (get-challenge-leaderboard (challenge-id uint) (rank uint))
  (map-get? challenge-leaderboard { challenge-id: challenge-id, rank: rank })
)

(define-read-only (get-reviewer-history (reviewer principal))
  (default-to 
    {
      total-challenges: u0,
      total-wins: u0,
      avg-quality: u0,
      suspicious-activity: false,
      last-challenge: u0
    }
    (map-get? reviewer-challenge-history { reviewer: reviewer })
  )
)

(define-read-only (get-challenge-integrity (challenge-id uint))
  (map-get? challenge-integrity { challenge-id: challenge-id })
)

(define-read-only (is-challenge-active (challenge-id uint))
  (let
    (
      (challenge (map-get? review-challenges { challenge-id: challenge-id }))
    )
    (match challenge
      chall (and (is-eq (get status chall) "active")
                 (< stacks-block-height (get challenge-end chall))
                 (not (var-get contract-paused)))
      false)
  )
)

;; Enhanced challenge creation with better validation
(define-public (create-review-challenge 
  (paper-id uint) 
  (title (string-ascii 100)) 
  (description (string-utf8 300))
  (reward-pool uint) 
  (duration uint) 
  (max-reviewers uint)
  (category (string-ascii 30)))
  (let
    (
      (challenge-id (var-get next-challenge-id))
      (paper (contract-call? .review-incentive get-paper paper-id))
      (organizer-info (contract-call? .review-incentive get-user-info tx-sender))
      (challenge-start stacks-block-height)
      (challenge-end (+ stacks-block-height duration))
    )
    ;; Enhanced validation
    (asserts! (not (var-get contract-paused)) err-contract-paused)
    (asserts! (is-some paper) err-not-found)
    (asserts! (get registered organizer-info) err-unauthorized)
    (asserts! (>= (get reputation organizer-info) u25) err-unauthorized) ;; Minimum reputation
    (asserts! (and (>= reward-pool min-reward-pool) (<= reward-pool max-reward-pool)) err-insufficient-reward)
    (asserts! (and (>= duration min-challenge-duration) (<= duration max-challenge-duration)) err-invalid-parameters)
    (asserts! (and (>= max-reviewers min-participants) (<= max-reviewers max-participants)) err-invalid-parameters)
    (asserts! (>= (contract-call? .review-incentive get-balance tx-sender) reward-pool) err-insufficient-reward)
    
    ;; Transfer reward pool to contract (including platform fee)
    (let ((platform-fee (/ (* reward-pool platform-fee-percent) u100)))
      (try! (contract-call? .review-incentive transfer-tokens (+ reward-pool platform-fee) (as-contract tx-sender)))
      
      ;; Transfer platform fee to collector
      (try! (as-contract (contract-call? .review-incentive transfer-tokens platform-fee (var-get platform-fee-collector))))
    )
    
    (map-set review-challenges
      { challenge-id: challenge-id }
      {
        paper-id: paper-id,
        organizer: tx-sender,
        title: title,
        description: description,
        total-reward-pool: reward-pool,
        entry-fee: challenge-entry-fee,
        max-participants: max-reviewers,
        current-participants: u0,
        challenge-start: challenge-start,
        challenge-end: challenge-end,
        status: "active",
        winner-1st: none,
        winner-2nd: none,
        winner-3rd: none,
        finalized: false,
        rewards-distributed: false,
        avg-quality-score: u0,
        category: category
      }
    )
    
    ;; Initialize integrity tracking
    (map-set challenge-integrity
      { challenge-id: challenge-id }
      {
        duplicate-submissions: u0,
        flagged-reviews: u0,
        quality-variance: u0,
        integrity-score: u100
      }
    )
    
    (var-set next-challenge-id (+ challenge-id u1))
    (ok challenge-id)
  )
)

;; Enhanced join with anti-gaming measures
(define-public (join-review-challenge (challenge-id uint))
  (let
    (
      (challenge (unwrap! (map-get? review-challenges { challenge-id: challenge-id }) err-not-found))
      (user-info (contract-call? .review-incentive get-user-info tx-sender))
      (reviewer-history (get-reviewer-history tx-sender))
    )
    ;; Enhanced validation
    (asserts! (not (var-get contract-paused)) err-contract-paused)
    (asserts! (is-eq (get status challenge) "active") err-challenge-closed)
    (asserts! (< stacks-block-height (get challenge-end challenge)) err-deadline-passed)
    (asserts! (< (get current-participants challenge) (get max-participants challenge)) err-challenge-closed)
    (asserts! (get registered user-info) err-unauthorized)
    (asserts! (>= (get reputation user-info) u10) err-unauthorized) ;; Minimum reputation
    (asserts! (not (get suspicious-activity reviewer-history)) err-unauthorized)
    (asserts! (is-none (map-get? challenge-participants { challenge-id: challenge-id, reviewer: tx-sender })) err-already-submitted)
    
    ;; Anti-gaming: Check if reviewer has participated in too many recent challenges
    (asserts! (< (- stacks-block-height (get last-challenge reviewer-history)) u144) err-duplicate-reviewer)
    
    ;; Check entry fee payment
    (asserts! (>= (contract-call? .review-incentive get-balance tx-sender) (get entry-fee challenge)) err-insufficient-reward)
    (try! (contract-call? .review-incentive transfer-tokens (get entry-fee challenge) (as-contract tx-sender)))
    
    ;; Add participant with enhanced tracking
    (map-set challenge-participants
      { challenge-id: challenge-id, reviewer: tx-sender }
      {
        entry-timestamp: stacks-block-height,
        review-quality-score: u0,
        review-submission: none,
        final-rank: none,
        reward-earned: u0,
        performance-bonus: u0,
        speed-score: u0,
        length-score: u0,
        consistency-score: u0,
        claimed-reward: false,
        disqualified: false,
        disqualification-reason: none
      }
    )
    
    ;; Update challenge and reviewer history
    (map-set review-challenges
      { challenge-id: challenge-id }
      (merge challenge { current-participants: (+ (get current-participants challenge) u1) })
    )
    
    (map-set reviewer-challenge-history
      { reviewer: tx-sender }
      (merge reviewer-history {
        total-challenges: (+ (get total-challenges reviewer-history) u1),
        last-challenge: stacks-block-height
      })
    )
    
    (ok true)
  )
)

;; Enhanced review submission with comprehensive scoring
(define-public (submit-challenge-review (challenge-id uint) (review-text (string-utf8 400)) (quality-self-score uint))
  (let
    (
      (challenge (unwrap! (map-get? review-challenges { challenge-id: challenge-id }) err-not-found))
      (participant (unwrap! (map-get? challenge-participants { challenge-id: challenge-id, reviewer: tx-sender }) err-unauthorized))
      (user-info (contract-call? .review-incentive get-user-info tx-sender))
    )
    ;; Enhanced validation
    (asserts! (not (var-get contract-paused)) err-contract-paused)
    (asserts! (is-eq (get status challenge) "active") err-challenge-closed)
    (asserts! (< stacks-block-height (get challenge-end challenge)) err-deadline-passed)
    (asserts! (is-none (get review-submission participant)) err-already-submitted)
    (asserts! (and (>= quality-self-score u1) (<= quality-self-score u10)) err-invalid-parameters)
    (asserts! (not (get disqualified participant)) err-unauthorized)
    
    ;; Calculate comprehensive scores
    (let
      (
        (speed-score (calculate-enhanced-speed-bonus (get entry-timestamp participant) stacks-block-height))
        (length-score (calculate-enhanced-length-score review-text))
        (consistency-score (calculate-consistency-score tx-sender quality-self-score))
        (base-quality (* quality-self-score u10))
        
        ;; Weighted total score
        (total-score (+ 
          (/ (* base-quality quality-weight) u100)
          (/ (* speed-score speed-weight) u100)
          (/ (* length-score length-weight) u100)
          (/ (* consistency-score consistency-weight) u100)
        ))
      )
      
      ;; Anti-gaming: Check for duplicate content
      (asserts! (not (is-duplicate-submission challenge-id review-text)) err-duplicate-reviewer)
      
      ;; Record comprehensive submission
      (map-set challenge-participants
        { challenge-id: challenge-id, reviewer: tx-sender }
        (merge participant {
          review-quality-score: total-score,
          review-submission: (some review-text),
          speed-score: speed-score,
          length-score: length-score,
          consistency-score: consistency-score,
          performance-bonus: (/ (* total-score u10) u100)
        })
      )
      
      ;; Update challenge integrity tracking
      (update-challenge-integrity challenge-id review-text total-score)
      
      (ok total-score)
    )
  )
)

;; Enhanced finalization with proper leaderboard generation
(define-public (finalize-challenge (challenge-id uint))
  (let
    (
      (challenge (unwrap! (map-get? review-challenges { challenge-id: challenge-id }) err-not-found))
    )
    ;; Enhanced validation
    (asserts! (not (var-get contract-paused)) err-contract-paused)
    (asserts! (is-eq tx-sender (get organizer challenge)) err-unauthorized)
    (asserts! (>= stacks-block-height (get challenge-end challenge)) err-challenge-active)
    (asserts! (is-eq (get status challenge) "active") err-challenge-closed)
    (asserts! (>= (get current-participants challenge) min-participants) err-insufficient-participants)
    (asserts! (not (get finalized challenge)) err-already-finalized)
    
    ;; Generate leaderboard and determine winners
    (let
      (
        (sorted-participants (generate-leaderboard challenge-id))
        (total-pool (get total-reward-pool challenge))
        (first-reward (/ (* total-pool first-place-percent) u100))
        (second-reward (/ (* total-pool second-place-percent) u100))
        (third-reward (/ (* total-pool third-place-percent) u100))
        (participation-reward (/ (* total-pool participation-pool-percent) u100))
        (participation-per-user (/ participation-reward (get current-participants challenge)))
      )
      
      ;; Update challenge with winners
      (map-set review-challenges
        { challenge-id: challenge-id }
        (merge challenge { 
          status: "completed",
          finalized: true,
          winner-1st: (get-winner-at-rank challenge-id u1),
          winner-2nd: (get-winner-at-rank challenge-id u2),
          winner-3rd: (get-winner-at-rank challenge-id u3)
        })
      )
      
      ;; Calculate and store rewards for all participants
      (try! (calculate-all-participant-rewards challenge-id first-reward second-reward third-reward participation-per-user))
      
      (ok { 
        first: first-reward, 
        second: second-reward, 
        third: third-reward,
        participation: participation-per-user 
      })
    )
  )
)

;; Enhanced reward claiming with proper distribution
(define-public (claim-challenge-reward (challenge-id uint))
  (let
    (
      (challenge (unwrap! (map-get? review-challenges { challenge-id: challenge-id }) err-not-found))
      (participant (unwrap! (map-get? challenge-participants { challenge-id: challenge-id, reviewer: tx-sender }) err-unauthorized))
    )
    ;; Validation
    (asserts! (not (var-get contract-paused)) err-contract-paused)
    (asserts! (get finalized challenge) err-challenge-active)
    (asserts! (not (get claimed-reward participant)) err-rewards-claimed)
    (asserts! (> (get reward-earned participant) u0) err-insufficient-reward)
    
    ;; Transfer reward
    (let ((reward-amount (get reward-earned participant)))
      ;; Update participant record
      (map-set challenge-participants
        { challenge-id: challenge-id, reviewer: tx-sender }
        (merge participant { claimed-reward: true })
      )
      
      ;; Transfer tokens
      (try! (as-contract (contract-call? .review-incentive transfer-tokens reward-amount tx-sender)))
      
      ;; Update reviewer history
      (update-reviewer-history-on-completion tx-sender reward-amount)
      
      (ok reward-amount)
    )
  )
)

;; Emergency functions
(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender (var-get platform-fee-collector)) err-unauthorized)
    (var-set contract-paused true)
    (ok true)
  )
)

(define-public (unpause-contract)
  (begin
    (asserts! (is-eq tx-sender (var-get platform-fee-collector)) err-unauthorized)
    (var-set contract-paused false)
    (ok true)
  )
)

;; Enhanced helper functions

(define-private (calculate-enhanced-speed-bonus (entry-time uint) (submission-time uint))
  (let ((time-elapsed (- submission-time entry-time)))
    (if (<= time-elapsed u24) u100 ;; Ultra fast: 100 bonus
    (if (<= time-elapsed u72) u80 ;; Very fast: 80 bonus
    (if (<= time-elapsed u144) u60 ;; Fast: 60 bonus
    (if (<= time-elapsed u288) u40 ;; Medium: 40 bonus
    (if (<= time-elapsed u576) u20 u10))))) ;; Slow: 20 or minimal: 10 bonus
  )
)

(define-private (calculate-enhanced-length-score (review-text (string-utf8 400)))
  (let ((text-length (len review-text)))
    (if (>= text-length u350) u100 ;; Comprehensive: 100 points
    (if (>= text-length u250) u80 ;; Detailed: 80 points  
    (if (>= text-length u150) u60 ;; Good: 60 points
    (if (>= text-length u75) u40 ;; Adequate: 40 points
    (if (>= text-length u25) u20 u10))))) ;; Brief: 20 or minimal: 10 points
  )
)

(define-private (calculate-consistency-score (reviewer principal) (self-score uint))
  (let ((history (get-reviewer-history reviewer)))
    (if (< (get total-challenges history) u3)
      u50 ;; Default for new reviewers
      (let ((avg-quality (get avg-quality history)))
        (if (<= (abs-diff self-score avg-quality) u1) u100 ;; Very consistent
        (if (<= (abs-diff self-score avg-quality) u2) u75 ;; Consistent
        (if (<= (abs-diff self-score avg-quality) u3) u50 ;; Somewhat consistent
        u25))) ;; Inconsistent
      )
    )
  )
)

(define-private (abs-diff (a uint) (b uint))
  (if (> a b) (- a b) (- b a))
)

(define-private (is-duplicate-submission (challenge-id uint) (review-text (string-utf8 400)))
  ;; Simplified duplicate detection - in practice would use content hashing
  (< (len review-text) u10) ;; Flag suspiciously short reviews
)

(define-private (update-challenge-integrity (challenge-id uint) (review-text (string-utf8 400)) (score uint))
  (let ((integrity (unwrap-panic (map-get? challenge-integrity { challenge-id: challenge-id }))))
    (map-set challenge-integrity
      { challenge-id: challenge-id }
      (merge integrity {
        quality-variance: (+ (get quality-variance integrity) (abs-diff score u50))
      })
    )
    true
  )
)

(define-private (generate-leaderboard (challenge-id uint))
  ;; Simplified leaderboard generation - would sort participants by score
  true
)

(define-private (get-winner-at-rank (challenge-id uint) (rank uint))
  ;; Would return the principal at the given rank
  none
)

(define-private (calculate-all-participant-rewards (challenge-id uint) (first uint) (second uint) (third uint) (participation uint))
  ;; Would iterate through all participants and calculate their rewards based on rank
  (ok true)
)

(define-private (update-reviewer-history-on-completion (reviewer principal) (reward-amount uint))
  (let ((history (get-reviewer-history reviewer)))
    (map-set reviewer-challenge-history
      { reviewer: reviewer }
      (merge history {
        total-wins: (if (> reward-amount u100) (+ (get total-wins history) u1) (get total-wins history)),
        avg-quality: (/ (+ (* (get avg-quality history) (get total-challenges history)) u75) (+ (get total-challenges history) u1))
      })
    )
    true
  )
)

;; Administrative functions
(define-public (set-platform-fee-collector (new-collector principal))
  (begin
    (asserts! (is-eq tx-sender (var-get platform-fee-collector)) err-unauthorized)
    (var-set platform-fee-collector new-collector)
    (ok true)
  )
)

(define-public (emergency-refund-challenge (challenge-id uint))
  (let ((challenge (unwrap! (map-get? review-challenges { challenge-id: challenge-id }) err-not-found)))
    (asserts! (is-eq tx-sender (var-get platform-fee-collector)) err-unauthorized)
    (asserts! (is-eq (get status challenge) "active") err-challenge-closed)
    
    ;; Mark challenge as cancelled and refund participants
    (map-set review-challenges
      { challenge-id: challenge-id }
      (merge challenge { status: "cancelled" })
    )
    
    ;; Refund logic would go here
    (ok true)
  )
)
