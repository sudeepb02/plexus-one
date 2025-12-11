import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import { http } from 'wagmi';
import { base, baseSepolia, unichain, unichainSepolia } from 'wagmi/chains';

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
