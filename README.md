# 🔬 Peer Review Incentivization Smart Contract

This Clarity smart contract implements a decentralized peer review system for academic research, incentivizing honest and quality reviews through token rewards.

## 🌟 Features

- 🧪 Submit research papers with attached token rewards
- 📝 Provide peer reviews for submitted papers
- 🏆 Earn tokens for quality reviews
- 📊 Build reputation as a researcher or reviewer
- 🔐 Admin controls for token distribution and system management

## 📋 Contract Overview

The `review-incentive` contract creates an ecosystem where:

1. Researchers can submit papers with attached token rewards
2. Reviewers can provide ratings and comments on papers
3. Reviewers receive tokens for their contributions
4. All participants build reputation over time

## 🚀 Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) installed
- Basic understanding of Clarity and Stacks blockchain

### 💻 Usage

#### Register as a User

```clarity
(contract-call? .review-incentive register-user u2) ;; Register as a researcher (role 2)
(contract-call? .review-incentive register-user u3) ;; Register as a reviewer (role 3)
```

#### Submit a Paper

```clarity
;; Submit a paper with title, abstract, and 100 token reward
(contract-call? .review-incentive submit-paper "Blockchain Applications in Science" "This paper explores..." u100)
```

#### Submit a Review

```clarity
;; Submit a review for paper #1 with rating (1-5) and comments
(contract-call? .review-incentive submit-review u1 u4 "This research is promising because...")
```

#### Distribute Rewards

```clarity
;; Admin distributes rewards to a reviewer for paper #1
(contract-call? .review-incentive distribute-rewards u1 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
```

#### Transfer Tokens

```clarity
;; Transfer 50 tokens to another user
(contract-call? .review-incentive transfer-tokens u50 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
```

## 🔍 Key Functions

- `register-user`: Join the platform as a researcher or reviewer
- `submit-paper`: Submit a research paper with reward tokens
- `submit-review`: Provide a review for a paper
- `distribute-rewards`: Admin distributes tokens to reviewers
- `update-reputation`: Admin updates a user's reputation
- `mint-tokens`: Admin mints new tokens
- `transfer-tokens`: Transfer tokens between users
- `close-paper`: Mark a paper as closed for reviews

## 📊 Data Structures

- `users`: Tracks user roles, reputation, and registration status
- `papers`: Stores paper details, rewards, and status
- `reviews`: Contains review ratings, comments, and reward status

## 🔒 Security Features

- Role-based access controls
- Validation for all operations
- Prevention of self-reviews
- Balance checks for token operations