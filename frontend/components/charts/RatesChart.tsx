'use client';

import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';

// Mock data for the chart - replace with actual data later
const mockData = [
  { date: 'Jan 1', fixedRate: 4.2, variableRate: 3.8 },
  { date: 'Jan 8', fixedRate: 4.5, variableRate: 4.1 },
  { date: 'Jan 15', fixedRate: 4.8, variableRate: 4.3 },
  { date: 'Jan 22', fixedRate: 5.0, variableRate: 4.5 },
  { date: 'Jan 29', fixedRate: 5.2, variableRate: 4.7 },
  { date: 'Feb 5', fixedRate: 5.3, variableRate: 4.8 },
  { date: 'Feb 12', fixedRate: 5.25, variableRate: 4.8 },
];

export function RatesChart() {
  return (
    <div className="bg-white dark:bg-[#161b22] rounded-lg border border-gray-200 dark:border-[#30363d] shadow-sm">
      <div className="border-b border-gray-200 dark:border-[#30363d] p-4">
        <h2 className="text-lg font-semibold text-gray-900 dark:text-white">
          Rate History
        </h2>
        <p className="text-xs text-gray-600 dark:text-gray-400 mt-1">
          Fixed vs Variable rates over time
        </p>
      </div>

      <div className="p-4">
        <ResponsiveContainer width="100%" height={280}>
          <LineChart data={mockData}>
            <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" className="dark:stroke-[#30363d]" opacity={0.5} />
            <XAxis 
              dataKey="date" 
              stroke="#9ca3af"
              style={{ fontSize: '11px' }}
              tick={{ fill: '#6b7280' }}
            />
            <YAxis 
              stroke="#9ca3af"
              style={{ fontSize: '11px' }}
              tick={{ fill: '#6b7280' }}
              tickFormatter={(value) => `${value}%`}
            />
            <Tooltip
              contentStyle={{
                backgroundColor: '#ffffff',
                border: '1px solid #e5e7eb',
                borderRadius: '8px',
                boxShadow: '0 4px 6px -1px rgb(0 0 0 / 0.1)',
                fontSize: '12px',
              }}
              formatter={(value: number) => [`${value.toFixed(2)}%`, '']}
            />
            <Legend 
              wrapperStyle={{ fontSize: '12px', paddingTop: '16px' }}
            />
            <Line
              type="monotone"
              dataKey="fixedRate"
              stroke="#2563eb"
              strokeWidth={2}
              dot={{ fill: '#2563eb', r: 3 }}
              activeDot={{ r: 5 }}
              name="Fixed Rate"
            />
            <Line
              type="monotone"
              dataKey="variableRate"
              stroke="#7c3aed"
              strokeWidth={2}
              dot={{ fill: '#7c3aed', r: 3 }}
              activeDot={{ r: 5 }}
              name="Variable Rate"
            />
          </LineChart>
        </ResponsiveContainer>

        <div className="mt-4 grid grid-cols-2 gap-3">
          <div className="p-3 bg-blue-50 dark:bg-blue-950/20 rounded-lg border border-blue-200 dark:border-blue-900/50">
            <div className="text-xs text-gray-600 dark:text-gray-400 mb-1">Current Fixed</div>
            <div className="text-xl font-semibold text-blue-600 dark:text-blue-400">5.25%</div>
          </div>
          <div className="p-3 bg-purple-50 dark:bg-purple-950/20 rounded-lg border border-purple-200 dark:border-purple-900/50">
            <div className="text-xs text-gray-600 dark:text-gray-400 mb-1">Current Variable</div>
            <div className="text-xl font-semibold text-purple-600 dark:text-purple-400">4.80%</div>
          </div>
        </div>
      </div>
    </div>
  );
}
