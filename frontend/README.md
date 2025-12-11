# Plexus Frontend

A beautiful, user-friendly interface for trading interest rate swaps on Uniswap V4.

## Features

- 🎨 **Beautiful UI**: Clean, modern interface with dark mode support
- ⚡ **Fast Swaps**: Trade between fixed and variable rates instantly
- 📊 **Real-time Charts**: Visualize rate history and market trends
- 🔗 **Wallet Integration**: Connect with RainbowKit (supports all major wallets)
- 📱 **Responsive**: Works seamlessly on desktop, tablet, and mobile

## Getting Started

### Prerequisites

- Node.js 18+ 
- npm or yarn

### Installation

1. Install dependencies:
```bash
npm install
```

2. Copy the environment variables:
```bash
cp .env.example .env.local
```

3. Update `.env.local` with your configuration:
   - Get a WalletConnect Project ID from https://cloud.walletconnect.com/
   - Add your deployed contract addresses

### Development

Run the development server:

```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) to see the app.

### Build

Build for production:

```bash
npm run build
npm start
```

## Project Structure

```
frontend/
├── app/                    # Next.js app directory
│   ├── page.tsx           # Main landing page
│   ├── layout.tsx         # Root layout with providers
│   ├── providers.tsx      # Web3 and context providers
│   └── globals.css        # Global styles
├── components/
│   ├── swap/              # Swap interface components
│   │   └── SwapCard.tsx   # Main swap card
│   ├── charts/            # Chart components
│   │   └── RatesChart.tsx # Rate history chart
│   └── trades/            # Trade history components
│       └── TradeHistory.tsx
└── lib/
    ├── wagmi.ts           # Wagmi configuration
    └── SwapContext.tsx    # Swap state management
```

## Tech Stack

- **Framework**: Next.js 15 with App Router
- **Styling**: Tailwind CSS
- **Web3**: Wagmi + Viem + RainbowKit
- **Charts**: Recharts
- **Icons**: Lucide React

## Customization

### Colors

Edit the CSS variables in `app/globals.css` to customize the theme:

```css
:root {
  --primary: #6366f1;    /* Indigo */
  --accent: #8b5cf6;     /* Purple */
  /* ... more colors */
}
```

### Networks

Add or remove networks in `lib/wagmi.ts`:

```typescript
chains: [mainnet, sepolia, base, baseSepolia, localhost]
```

## TODO

- [ ] Connect to actual smart contracts
- [ ] Implement real swap logic
- [ ] Add transaction history
- [ ] Add user portfolio page
- [ ] Add liquidity management UI
- [ ] Integrate with subgraph for real data
- [ ] Add notifications/toasts
- [ ] Add analytics tracking

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT
