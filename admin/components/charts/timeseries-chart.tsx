'use client';

import {
  Area,
  AreaChart,
  CartesianGrid,
  Legend,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';

interface SeriesConfig {
  dataKey: string;
  label: string;
  color: string;
}

interface TimeseriesChartProps {
  data: Array<Record<string, string | number>>;
  xKey: string;
  series: SeriesConfig[];
  height?: number;
  variant?: 'line' | 'area';
  xFormatter?: (value: string | number) => string;
  yFormatter?: (value: number) => string;
}

export function TimeseriesChart({
  data,
  xKey,
  series,
  height = 300,
  variant = 'area',
  xFormatter,
  yFormatter,
}: TimeseriesChartProps) {
  const ChartComponent = variant === 'area' ? AreaChart : LineChart;

  return (
    <ResponsiveContainer width="100%" height={height}>
      <ChartComponent data={data} margin={{ top: 8, right: 16, left: 0, bottom: 0 }}>
        <defs>
          {series.map((s) => (
            <linearGradient
              key={s.dataKey}
              id={`gradient-${s.dataKey}`}
              x1="0"
              y1="0"
              x2="0"
              y2="1"
            >
              <stop offset="5%" stopColor={s.color} stopOpacity={0.3} />
              <stop offset="95%" stopColor={s.color} stopOpacity={0} />
            </linearGradient>
          ))}
        </defs>

        <CartesianGrid
          strokeDasharray="3 3"
          vertical={false}
          className="stroke-border"
        />
        <XAxis
          dataKey={xKey}
          tickLine={false}
          axisLine={false}
          tickFormatter={xFormatter}
          className="text-xs"
        />
        <YAxis
          tickLine={false}
          axisLine={false}
          tickFormatter={yFormatter}
          className="text-xs"
        />
        <Tooltip
          contentStyle={{
            backgroundColor: 'hsl(var(--popover))',
            border: '1px solid hsl(var(--border))',
            borderRadius: '0.5rem',
          }}
          labelFormatter={xFormatter}
          formatter={(value: number) =>
            yFormatter ? yFormatter(value) : value.toLocaleString()
          }
        />
        <Legend
          iconType="circle"
          wrapperStyle={{ fontSize: '12px', paddingTop: '8px' }}
        />

        {series.map((s) =>
          variant === 'area' ? (
            <Area
              key={s.dataKey}
              type="monotone"
              dataKey={s.dataKey}
              name={s.label}
              stroke={s.color}
              fill={`url(#gradient-${s.dataKey})`}
              strokeWidth={2}
            />
          ) : (
            <Line
              key={s.dataKey}
              type="monotone"
              dataKey={s.dataKey}
              name={s.label}
              stroke={s.color}
              strokeWidth={2}
              dot={false}
            />
          ),
        )}
      </ChartComponent>
    </ResponsiveContainer>
  );
}
