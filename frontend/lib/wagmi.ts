import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import { http } from 'wagmi';
import { base, baseSepolia } from 'wagmi/chains';

// Define Unichain and Unichain Sepolia
const unichain = {
  id: 1301,
  name: 'Unichain',
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: {
    default: { http: ['https://rpc.unichain.org'] },
  },
  blockExplorers: {
    default: { name: 'Uniscan', url: 'https://uniscan.xyz' },
  },
} as const;

const unichainSepolia = {
  id: 1301537,
  name: 'Unichain Sepolia',
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: {
    default: { http: ['https://sepolia.unichain.org'] },
  },
  blockExplorers: {
    default: { name: 'Uniscan', url: 'https://sepolia.uniscan.xyz' },
  },
  testnet: true,
} as const;

export const config = getDefaultConfig({
  appName: 'PlexusOne',
  projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || 'YOUR_PROJECT_ID',
  chains: [unichain, unichainSepolia, base, baseSepolia],
  transports: {
    [unichain.id]: http(),
    [unichainSepolia.id]: http(),
    [base.id]: http(),
    [baseSepolia.id]: http(),
  },
  ssr: true,
});
