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
    <div className="bg-white dark:bg-[#171717] rounded-3xl shadow-2xl p-6 border border-gray-200 dark:border-[#404040]">
      <div className="mb-6">
        <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-2">
          Rate History
        </h2>
        <p className="text-sm text-gray-500 dark:text-gray-400">
          Fixed vs Variable rates over time
        </p>
      </div>

      <ResponsiveContainer width="100%" height={300}>
        <LineChart data={mockData}>
          <CartesianGrid strokeDasharray="3 3" stroke="#404040" opacity={0.3} />
          <XAxis 
            dataKey="date" 
            stroke="#9ca3af"
            style={{ fontSize: '12px' }}
          />
          <YAxis 
            stroke="#9ca3af"
            style={{ fontSize: '12px' }}
            tickFormatter={(value) => `${value}%`}
          />
          <Tooltip
            contentStyle={{
              backgroundColor: 'rgba(23, 23, 23, 0.95)',
              border: '1px solid #404040',
              borderRadius: '12px',
              color: '#fff',
            }}
            formatter={(value: number) => [`${value.toFixed(2)}%`, '']}
          />
          <Legend 
            wrapperStyle={{ fontSize: '14px', paddingTop: '20px' }}
          />
          <Line
            type="monotone"
            dataKey="fixedRate"
            stroke="#6366f1"
            strokeWidth={3}
            dot={{ fill: '#6366f1', r: 4 }}
            activeDot={{ r: 6 }}
            name="Fixed Rate"
          />
          <Line
            type="monotone"
            dataKey="variableRate"
            stroke="#8b5cf6"
            strokeWidth={3}
            dot={{ fill: '#8b5cf6', r: 4 }}
            activeDot={{ r: 6 }}
            name="Variable Rate"
          />
        </LineChart>
      </ResponsiveContainer>

      <div className="mt-6 grid grid-cols-2 gap-4">
        <div className="p-4 bg-indigo-50 dark:bg-indigo-950/30 rounded-2xl border border-indigo-200 dark:border-indigo-900">
          <div className="text-sm text-gray-600 dark:text-gray-400 mb-1">Current Fixed</div>
          <div className="text-2xl font-bold text-indigo-600 dark:text-indigo-400">5.25%</div>
        </div>
        <div className="p-4 bg-purple-50 dark:bg-purple-950/30 rounded-2xl border border-purple-200 dark:border-purple-900">
          <div className="text-sm text-gray-600 dark:text-gray-400 mb-1">Current Variable</div>
          <div className="text-2xl font-bold text-purple-600 dark:text-purple-400">4.80%</div>
        </div>
      </div>
    </div>
  );
}
