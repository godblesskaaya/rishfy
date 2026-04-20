'use client';

import { useQuery } from '@tanstack/react-query';
import {
  Car,
  CreditCard,
  Receipt,
  Users,
} from 'lucide-react';

import { TimeseriesChart } from '@/components/charts/timeseries-chart';
import { KpiCard } from '@/components/kpi-card';
import { PageHeader } from '@/components/layout/page-header';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { overviewApi } from '@/lib/api/endpoints';
import { formatTZS } from '@/lib/utils';

export default function OverviewPage() {
  const kpis = useQuery({
    queryKey: ['overview', 'kpis'],
    queryFn: () => overviewApi.getKpis(),
  });

  const timeseries = useQuery({
    queryKey: ['overview', 'bookings-timeseries', 30],
    queryFn: () => overviewApi.getBookingsTimeseries(30),
  });

  const topRoutes = useQuery({
    queryKey: ['overview', 'top-routes', 10],
    queryFn: () => overviewApi.getTopRoutes(10),
  });

  return (
    <>
      <PageHeader
        title="Dashboard"
        description="Platform performance at a glance"
      />

      {/* KPI grid */}
      <div className="mb-8 grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-4">
        <KpiCard
          label="Total users"
          value={kpis.data?.total_users.toLocaleString() ?? '—'}
          delta={kpis.data?.delta_vs_last_week.users}
          icon={Users}
          loading={kpis.isLoading}
        />
        <KpiCard
          label="Active drivers"
          value={kpis.data?.active_drivers.toLocaleString() ?? '—'}
          icon={Car}
          loading={kpis.isLoading}
        />
        <KpiCard
          label="Bookings today"
          value={kpis.data?.bookings_today.toLocaleString() ?? '—'}
          delta={kpis.data?.delta_vs_last_week.bookings}
          icon={Receipt}
          loading={kpis.isLoading}
        />
        <KpiCard
          label="Gross revenue"
          value={formatTZS(kpis.data?.gross_revenue_tzs ?? 0)}
          delta={kpis.data?.delta_vs_last_week.revenue}
          icon={CreditCard}
          loading={kpis.isLoading}
        />
      </div>

      {/* Charts */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle>Bookings & Revenue</CardTitle>
            <CardDescription>Last 30 days</CardDescription>
          </CardHeader>
          <CardContent>
            {timeseries.isLoading ? (
              <div className="flex h-[300px] items-center justify-center text-muted-foreground">
                Loading chart...
              </div>
            ) : (
              <TimeseriesChart
                data={timeseries.data ?? []}
                xKey="date"
                series={[
                  {
                    dataKey: 'bookings',
                    label: 'Bookings',
                    color: 'hsl(var(--primary))',
                  },
                  {
                    dataKey: 'revenue',
                    label: 'Revenue (TZS)',
                    color: 'hsl(var(--accent))',
                  },
                ]}
                xFormatter={(v) => String(v).slice(5)}
              />
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Top routes</CardTitle>
            <CardDescription>By booking volume</CardDescription>
          </CardHeader>
          <CardContent>
            {topRoutes.isLoading ? (
              <p className="text-sm text-muted-foreground">Loading...</p>
            ) : topRoutes.data && topRoutes.data.length > 0 ? (
              <ul className="space-y-3">
                {topRoutes.data.map((route, idx) => (
                  <li
                    key={idx}
                    className="flex items-center justify-between gap-3 text-sm"
                  >
                    <div className="flex min-w-0 items-center gap-3">
                      <span className="flex h-6 w-6 items-center justify-center rounded-full bg-muted text-xs font-medium">
                        {idx + 1}
                      </span>
                      <span className="truncate">
                        {route.origin} → {route.destination}
                      </span>
                    </div>
                    <span className="shrink-0 text-muted-foreground">
                      {route.bookings}
                    </span>
                  </li>
                ))}
              </ul>
            ) : (
              <p className="text-sm text-muted-foreground">No data yet</p>
            )}
          </CardContent>
        </Card>
      </div>
    </>
  );
}
