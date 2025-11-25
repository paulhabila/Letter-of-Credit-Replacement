# 📜 Letter of Credit Replacement

A decentralized Letter of Credit system built on Stacks blockchain using Clarity smart contracts. This system replaces traditional banking letters of credit with trustless, on-chain agreements triggered by delivery confirmation. 🚀

## ✨ Features

- 🔒 **Trustless Escrow**: Funds are held securely in the smart contract
- 📦 **Delivery Confirmation**: Multiple parties can confirm delivery
- ⏰ **Automatic Expiration**: Built-in deadline management
- 💰 **Instant Settlement**: Payments released immediately upon confirmation
- 🔄 **Refund Protection**: Automatic refunds for expired or cancelled orders

## 🛠 How It Works

1. **Create Letter of Credit** 📝: Buyer creates an LC specifying seller, amount, and delivery deadline
2. **Fund the LC** 💵: Buyer deposits STX tokens into the contract
3. **Deliver Goods** 📦: Seller delivers goods to buyer
4. **Confirm Delivery** ✅: Authorized parties confirm successful delivery
5. **Release Payment** 💸: Funds are automatically transferred to seller

## 🎯 Usage

### Creating a Letter of Credit

```clarity
(contract-call? .letter-of-credit-replacement create-letter-of-credit 
  'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7  ;; seller address
  u1000000                                      ;; amount in microSTX
  u144000                                       ;; delivery deadline (block height)
  (some 'SP3K8BC0PPEVCV7NZ6QSRWPQ2JE9E5B6N3PA0KBR9) ;; optional delivery confirmer
)
```

### Funding the Letter of Credit

```clarity
(contract-call? .letter-of-credit-replacement fund-letter-of-credit u0) ;; LC ID
```

### Confirming Delivery

```clarity
(contract-call? .letter-of-credit-replacement confirm-delivery u0) ;; LC ID
```

### Releasing Payment

```clarity
(contract-call? .letter-of-credit-replacement release-payment u0) ;; LC ID
```

### Cancelling (if expired or unfunded)

```clarity
(contract-call? .letter-of-credit-replacement cancel-letter-of-credit u0) ;; LC ID
```

## 📊 Contract States

- **0** - Created: LC exists but not funded
- **1** - Funded: Buyer has deposited funds
- **2** - Delivered: Delivery has been confirmed
- **3** - Completed: Payment released to seller
- **4** - Cancelled: LC cancelled or expired

## 🔍 Read-Only Functions

- `get-letter-of-credit`: Get LC details by ID
- `get-lc-funds`: Check funds held for an LC
- `get-current-lc-counter`: Get total number of LCs created
- `is-buyer` / `is-seller`: Check user roles
- `get-lc-state`: Get current state of an LC
- `is-lc-active`: Check if LC is still active

## 🚦 Error Codes

- **100**: Unauthorized access
- **101**: LC already exists
- **102**: LC not found
- **103**: Invalid state transition
- **104**: Insufficient funds
- **105**: LC has expired

## 🏗 Development

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) CLI tool
- Node.js and npm

### Setup

```bash
# Install dependencies
npm install

# Run tests
clarinet test

# Check contract syntax
clarinet check
```

### Testing

```bash
# Run all tests
npm test

# Deploy to testnet
clarinet deploy --testnet
```



## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## ⚠️ Disclaimer

This is experimental software. Use at your own risk. Always audit smart contracts before using them with real funds.
