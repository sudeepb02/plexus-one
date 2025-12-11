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
    <div className="bg-white dark:bg-[#171717] rounded-3xl shadow-2xl p-6 border border-gray-200 dark:border-[#404040]">
      <div className="mb-6">
        <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-2">
          Recent Trades
        </h2>
        <p className="text-sm text-gray-500 dark:text-gray-400">
          Live trading activity across all markets
        </p>
      </div>

      <div className="space-y-3">
        {mockTrades.map((trade) => (
          <div
            key={trade.id}
            className="flex items-center justify-between p-4 bg-gray-50 dark:bg-[#262626] rounded-2xl border border-gray-200 dark:border-[#404040] hover:border-gray-300 dark:hover:border-[#505050] transition-colors"
          >
            <div className="flex items-center gap-4">
              <div
                className={`p-2 rounded-xl ${
                  trade.action === 'buy'
                    ? 'bg-green-100 dark:bg-green-950/30'
                    : 'bg-red-100 dark:bg-red-950/30'
                }`}
              >
                {trade.action === 'buy' ? (
                  <ArrowUpRight className="w-5 h-5 text-green-600 dark:text-green-400" />
                ) : (
                  <ArrowDownRight className="w-5 h-5 text-red-600 dark:text-red-400" />
                )}
              </div>
              <div>
                <div className="flex items-center gap-2">
                  <span className="font-semibold text-gray-900 dark:text-white">
                    {trade.action === 'buy' ? 'Buy' : 'Sell'} {trade.type === 'fixed' ? 'Fixed' : 'Variable'}
                  </span>
                  <span
                    className={`px-2 py-0.5 rounded-lg text-xs font-medium ${
                      trade.type === 'fixed'
                        ? 'bg-indigo-100 dark:bg-indigo-950/30 text-indigo-700 dark:text-indigo-300'
                        : 'bg-purple-100 dark:bg-purple-950/30 text-purple-700 dark:text-purple-300'
                    }`}
                  >
                    {trade.rate}%
                  </span>
                </div>
                <div className="text-sm text-gray-500 dark:text-gray-400 mt-1">
                  {trade.user} • {trade.timestamp}
                </div>
              </div>
            </div>
            <div className="text-right">
              <div className="font-bold text-gray-900 dark:text-white">
                ${trade.amount.toLocaleString()}
              </div>
              <div className="text-sm text-gray-500 dark:text-gray-400">USDC</div>
            </div>
          </div>
        ))}
      </div>

      <button className="w-full mt-4 py-3 text-center text-sm font-medium text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white transition-colors">
        View all trades →
      </button>
    </div>
  );
}
