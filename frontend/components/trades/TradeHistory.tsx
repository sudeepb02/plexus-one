'use client';

import { ArrowUpRight, ArrowDownRight } from 'lucide-react';

// Mock trade data - replace with actual on-chain data later
const mockTrades = [
  {
    id: 1,
    type: 'fixed',
    action: 'buy',
    amount: 1000,
    rate: 5.25,
    timestamp: '2 mins ago',
    user: '0x1234...5678',
  },
  {
    id: 2,
    type: 'variable',
    action: 'sell',
    amount: 500,
    rate: 4.80,
    timestamp: '5 mins ago',
    user: '0x8765...4321',
  },
  {
    id: 3,
    type: 'fixed',
    action: 'buy',
    amount: 2500,
    rate: 5.20,
    timestamp: '12 mins ago',
    user: '0xabcd...efgh',
  },
  {
    id: 4,
    type: 'variable',
    action: 'buy',
    amount: 750,
    rate: 4.75,
    timestamp: '18 mins ago',
    user: '0x9876...1234',
  },
  {
    id: 5,
    type: 'fixed',
    action: 'sell',
    amount: 1200,
    rate: 5.15,
    timestamp: '25 mins ago',
    user: '0xfedc...9876',
  },
];

export function TradeHistory() {
  return (
    <div className="bg-white dark:bg-[#161b22] rounded-lg border border-gray-200 dark:border-[#30363d] shadow-sm">
      <div className="border-b border-gray-200 dark:border-[#30363d] p-4">
        <h2 className="text-lg font-semibold text-gray-900 dark:text-white">
          Recent Trades
        </h2>
        <p className="text-xs text-gray-600 dark:text-gray-400 mt-1">
          Live trading activity across all markets
        </p>
      </div>

      <div className="divide-y divide-gray-200 dark:divide-[#30363d]">
        {mockTrades.map((trade) => (
          <div
            key={trade.id}
            className="flex items-center justify-between p-4 hover:bg-gray-50 dark:hover:bg-[#0d1117] transition-colors"
          >
            <div className="flex items-center gap-3">
              <div
                className={`p-2 rounded ${
                  trade.action === 'buy'
                    ? 'bg-green-50 dark:bg-green-950/20'
                    : 'bg-red-50 dark:bg-red-950/20'
                }`}
              >
                {trade.action === 'buy' ? (
                  <ArrowUpRight className="w-4 h-4 text-green-600 dark:text-green-400" />
                ) : (
                  <ArrowDownRight className="w-4 h-4 text-red-600 dark:text-red-400" />
                )}
              </div>
              <div>
                <div className="flex items-center gap-2">
                  <span className="font-medium text-sm text-gray-900 dark:text-white">
                    {trade.action === 'buy' ? 'Buy' : 'Sell'} {trade.type === 'fixed' ? 'Fixed' : 'Variable'}
                  </span>
                  <span
                    className={`px-2 py-0.5 rounded text-xs font-medium ${
                      trade.type === 'fixed'
                        ? 'bg-blue-50 dark:bg-blue-950/20 text-blue-700 dark:text-blue-300'
                        : 'bg-purple-50 dark:bg-purple-950/20 text-purple-700 dark:text-purple-300'
                    }`}
                  >
                    {trade.rate}%
                  </span>
                </div>
                <div className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                  {trade.user} • {trade.timestamp}
                </div>
              </div>
            </div>
            <div className="text-right">
              <div className="font-semibold text-sm text-gray-900 dark:text-white">
                ${trade.amount.toLocaleString()}
              </div>
              <div className="text-xs text-gray-500 dark:text-gray-400">USDC</div>
            </div>
          </div>
        ))}
      </div>

      <div className="p-3 border-t border-gray-200 dark:border-[#30363d]">
        <button className="w-full text-center text-xs font-medium text-gray-600 dark:text-gray-400 hover:text-blue-600 dark:hover:text-blue-400 transition-colors">
          View all trades →
        </button>
      </div>
    </div>
  );
}
