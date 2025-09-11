;; title: Review Challenge System
;; version: 1.0.0
;; summary: Competitive review challenges with performance-based rewards
;; description: Gamified review system with time-bounded challenges and tier-based incentives

;; constants
(define-constant err-not-found (err u601))
(define-constant err-unauthorized (err u602))
(define-constant err-challenge-closed (err u603))
(define-constant err-already-submitted (err u604))
(define-constant err-insufficient-reward (err u605))
(define-constant err-invalid-parameters (err u606))
(define-constant err-deadline-passed (err u607))
(define-constant err-challenge-active (err u608))

(define-constant min-challenge-duration u144) ;; ~1 day minimum
(define-constant max-challenge-duration u1440) ;; ~10 days maximum
(define-constant min-reward-pool u500) ;; Minimum total rewards
(define-constant max-participants u20)
(define-constant challenge-entry-fee u50) ;; Fee to join challenge

;; reward tiers
(define-constant first-place-percent u50) ;; 50% of pool
(define-constant second-place-percent u30) ;; 30% of pool  
(define-constant third-place-percent u20) ;; 20% of pool

;; data vars
(define-data-var next-challenge-id uint u1)

;; data maps
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
    status: (string-ascii 15), ;; active, completed, cancelled
    winner-1st: (optional principal),
    winner-2nd: (optional principal),
    winner-3rd: (optional principal)
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
    performance-bonus: uint
  }
)

(define-map challenge-leaderboard
  { challenge-id: uint, rank: uint }
  {
    reviewer: principal,
    total-score: uint,
    quality-metrics: uint,
    speed-bonus: uint,
    final-position: uint
  }
)

;; public functions

(define-public (create-review-challenge 
  (paper-id uint) 
  (title (string-ascii 100)) 
  (description (string-utf8 300))
  (reward-pool uint) 
  (duration uint) 
  (max-reviewers uint))
  (let
    (
      (challenge-id (var-get next-challenge-id))
      (paper (contract-call? .review-incentive get-paper paper-id))
      (challenge-start stacks-block-height)
      (challenge-end (+ stacks-block-height duration))
    )
    ;; Validate parameters
    (asserts! (is-some paper) err-not-found)
    (asserts! (>= reward-pool min-reward-pool) err-insufficient-reward)
    (asserts! (and (>= duration min-challenge-duration) (<= duration max-challenge-duration)) err-invalid-parameters)
    (asserts! (and (>= max-reviewers u3) (<= max-reviewers max-participants)) err-invalid-parameters)
    (asserts! (>= (contract-call? .review-incentive get-balance tx-sender) reward-pool) err-insufficient-reward)
    
    ;; Transfer reward pool to contract
    (try! (contract-call? .review-incentive transfer-tokens reward-pool (as-contract tx-sender)))
    
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
        winner-3rd: none
      }
    )
    
    (var-set next-challenge-id (+ challenge-id u1))
    (ok challenge-id)
  )
)

(define-public (join-review-challenge (challenge-id uint))
  (let
    (
      (challenge (unwrap! (map-get? review-challenges { challenge-id: challenge-id }) err-not-found))
      (user-info (contract-call? .review-incentive get-user-info tx-sender))
    )
    ;; Validate challenge and user eligibility
    (asserts! (is-eq (get status challenge) "active") err-challenge-closed)
    (asserts! (< stacks-block-height (get challenge-end challenge)) err-deadline-passed)
    (asserts! (< (get current-participants challenge) (get max-participants challenge)) err-challenge-closed)
    (asserts! (get registered user-info) err-unauthorized)
    (asserts! (is-none (map-get? challenge-participants { challenge-id: challenge-id, reviewer: tx-sender })) err-already-submitted)
    
    ;; Check entry fee payment
    (asserts! (>= (contract-call? .review-incentive get-balance tx-sender) (get entry-fee challenge)) err-insufficient-reward)
    (try! (contract-call? .review-incentive transfer-tokens (get entry-fee challenge) (as-contract tx-sender)))
    
    ;; Add participant
    (map-set challenge-participants
      { challenge-id: challenge-id, reviewer: tx-sender }
      {
        entry-timestamp: stacks-block-height,
        review-quality-score: u0,
        review-submission: none,
        final-rank: none,
        reward-earned: u0,
        performance-bonus: u0
      }
    )
    
    ;; Update participant count
    (map-set review-challenges
      { challenge-id: challenge-id }
      (merge challenge { current-participants: (+ (get current-participants challenge) u1) })
    )
    
    (ok true)
  )
)

(define-public (submit-challenge-review (challenge-id uint) (review-text (string-utf8 400)) (quality-self-score uint))
  (let
    (
      (challenge (unwrap! (map-get? review-challenges { challenge-id: challenge-id }) err-not-found))
      (participant (unwrap! (map-get? challenge-participants { challenge-id: challenge-id, reviewer: tx-sender }) err-unauthorized))
      (time-bonus (calculate-speed-bonus (get entry-timestamp participant) stacks-block-height))
    )
    ;; Validate submission
    (asserts! (is-eq (get status challenge) "active") err-challenge-closed)
    (asserts! (< stacks-block-height (get challenge-end challenge)) err-deadline-passed)
    (asserts! (is-none (get review-submission participant)) err-already-submitted)
    (asserts! (and (>= quality-self-score u1) (<= quality-self-score u10)) err-invalid-parameters)
    
    ;; Calculate quality score
    (let
      (
        (review-length-score (calculate-review-length-score review-text))
        (base-quality (* quality-self-score u10))
        (total-quality (+ base-quality review-length-score time-bonus))
      )
      
      ;; Record submission
      (map-set challenge-participants
        { challenge-id: challenge-id, reviewer: tx-sender }
        (merge participant {
          review-quality-score: total-quality,
          review-submission: (some review-text),
          performance-bonus: time-bonus
        })
      )
      
      (ok total-quality)
    )
  )
)

(define-public (finalize-challenge (challenge-id uint))
  (let
    (
      (challenge (unwrap! (map-get? review-challenges { challenge-id: challenge-id }) err-not-found))
    )
    ;; Only organizer can finalize
    (asserts! (is-eq tx-sender (get organizer challenge)) err-unauthorized)
    (asserts! (>= stacks-block-height (get challenge-end challenge)) err-challenge-active)
    (asserts! (is-eq (get status challenge) "active") err-challenge-closed)
    (asserts! (>= (get current-participants challenge) u3) err-invalid-parameters)
    
    ;; Calculate rewards and update challenge
    (let
      (
        (total-pool (get total-reward-pool challenge))
        (first-reward (/ (* total-pool first-place-percent) u100))
        (second-reward (/ (* total-pool second-place-percent) u100))
        (third-reward (/ (* total-pool third-place-percent) u100))
      )
      
      ;; Mark challenge as completed
      (map-set review-challenges
        { challenge-id: challenge-id }
        (merge challenge { status: "completed" })
      )
      
      ;; Distribute rewards would happen here based on leaderboard
      ;; For simplicity, we'll just mark completion
      (ok { first: first-reward, second: second-reward, third: third-reward })
    )
  )
)

(define-public (claim-challenge-reward (challenge-id uint))
  (let
    (
      (challenge (unwrap! (map-get? review-challenges { challenge-id: challenge-id }) err-not-found))
      (participant (unwrap! (map-get? challenge-participants { challenge-id: challenge-id, reviewer: tx-sender }) err-unauthorized))
    )
    ;; Validate claim eligibility
    (asserts! (is-eq (get status challenge) "completed") err-challenge-active)
    (asserts! (is-some (get final-rank participant)) err-unauthorized)
    (asserts! (is-eq (get reward-earned participant) u0) err-already-submitted)
    
    ;; Calculate reward based on rank
    (let
      (
        (rank (unwrap-panic (get final-rank participant)))
        (total-pool (get total-reward-pool challenge))
        (reward-amount (if (is-eq rank u1) (/ (* total-pool first-place-percent) u100)
                       (if (is-eq rank u2) (/ (* total-pool second-place-percent) u100)
                       (if (is-eq rank u3) (/ (* total-pool third-place-percent) u100) u0))))
      )
      
      ;; Update participant record
      (map-set challenge-participants
        { challenge-id: challenge-id, reviewer: tx-sender }
        (merge participant { reward-earned: reward-amount })
      )
      
      ;; Transfer reward
      (try! (as-contract (contract-call? .review-incentive transfer-tokens reward-amount tx-sender)))
      
      (ok reward-amount)
    )
  )
)

;; read-only functions

(define-read-only (get-review-challenge (challenge-id uint))
  (map-get? review-challenges { challenge-id: challenge-id })
)

(define-read-only (get-challenge-participant (challenge-id uint) (reviewer principal))
  (map-get? challenge-participants { challenge-id: challenge-id, reviewer: reviewer })
)

(define-read-only (get-challenge-leaderboard (challenge-id uint) (rank uint))
  (map-get? challenge-leaderboard { challenge-id: challenge-id, rank: rank })
)

(define-read-only (get-next-challenge-id)
  (var-get next-challenge-id)
)

(define-read-only (is-challenge-active (challenge-id uint))
  (let
    (
      (challenge (map-get? review-challenges { challenge-id: challenge-id }))
    )
    (match challenge
      chall (and (is-eq (get status chall) "active")
                 (< stacks-block-height (get challenge-end chall)))
      false)
  )
)

;; private helper functions

(define-private (calculate-speed-bonus (entry-time uint) (submission-time uint))
  (let ((time-elapsed (- submission-time entry-time)))
    (if (<= time-elapsed u72) u20 ;; Very fast: 20 bonus
    (if (<= time-elapsed u144) u15 ;; Fast: 15 bonus
    (if (<= time-elapsed u288) u10 ;; Medium: 10 bonus
    (if (<= time-elapsed u576) u5 u0)))) ;; Slow: 5 or 0 bonus
  )
)

(define-private (calculate-review-length-score (review-text (string-utf8 400)))
  (let ((text-length (len review-text)))
    (if (>= text-length u300) u25 ;; Comprehensive: 25 points
    (if (>= text-length u200) u20 ;; Detailed: 20 points  
    (if (>= text-length u100) u15 ;; Adequate: 15 points
    (if (>= text-length u50) u10 u5)))) ;; Brief: 10 or minimal: 5 points
  )
)
