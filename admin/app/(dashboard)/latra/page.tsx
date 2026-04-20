'use client';

import { useQuery } from '@tanstack/react-query';
import type { ColumnDef } from '@tanstack/react-table';
import { Download, ShieldCheck } from 'lucide-react';
import { useState } from 'react';

import { DataTable } from '@/components/data-table/data-table';
import { KpiCard } from '@/components/kpi-card';
import { PageHeader } from '@/components/layout/page-header';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { latraApi } from '@/lib/api/endpoints';
import { formatTZS, formatDistance } from '@/lib/utils';
import type { LatraTripRecord } from '@/types/api';

const columns: ColumnDef<LatraTripRecord>[] = [
  {
    accessorKey: 'trip_id',
    header: 'Trip ID',
    cell: ({ row }) => (
      <span className="font-mono text-xs">
        {row.original.trip_id.slice(0, 8)}...
      </span>
    ),
  },
  {
    accessorKey: 'vehicle_registration',
    header: 'Vehicle',
    cell: ({ row }) => (
      <span className="font-mono">{row.original.vehicle_registration}</span>
    ),
  },
  {
    accessorKey: 'driver_license_number',
    header: 'Driver License',
    cell: ({ row }) => (
      <span className="font-mono text-xs">
        {row.original.driver_license_number}
      </span>
    ),
  },
  {
    accessorKey: 'start_time',
    header: 'Start',
    cell: ({ row }) => (
      <span className="text-xs">{row.original.start_time}</span>
    ),
  },
  {
    accessorKey: 'trip_distance',
    header: 'Distance',
    cell: ({ row }) => formatDistance(row.original.trip_distance),
  },
  {
    accessorKey: 'total_fare_amount',
    header: 'Fare',
    cell: ({ row }) => formatTZS(row.original.total_fare_amount),
  },
  {
    accessorKey: 'rating',
    header: 'Rating',
    cell: ({ row }) =>
      row.original.rating > 0 ? `★ ${row.original.rating}` : '—',
  },
];

export default function LatraPage() {
  const today = new Date().toISOString().split('T')[0]!;
  const firstOfMonth = `${today.slice(0, 8)}01`;

  const [startDate, setStartDate] = useState(firstOfMonth);
  const [endDate, setEndDate] = useState(today);

  const stats = useQuery({
    queryKey: ['latra', 'stats'],
    queryFn: () => latraApi.getComplianceStats(),
  });

  const trips = useQuery({
    queryKey: ['latra', 'trips', startDate, endDate],
    queryFn: () => latraApi.getTrips({ startDate, endDate }),
    enabled: Boolean(startDate && endDate),
  });

  function downloadCsv() {
    const records = trips.data?.trips ?? [];
    if (records.length === 0) return;

    const headers = Object.keys(records[0]!).join(',');
    const rows = records
      .map((r) => Object.values(r).map((v) => `"${v}"`).join(','))
      .join('\n');
    const csv = `${headers}\n${rows}`;

    const blob = new Blob([csv], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `latra-trips-${startDate}-to-${endDate}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <>
      <PageHeader
        title="LATRA Compliance"
        description="Regulatory reporting for Tanzania's Land Transport Regulatory Authority"
        actions={
          <Button onClick={downloadCsv} disabled={!trips.data?.trips.length}>
            <Download className="mr-2 h-4 w-4" />
            Export CSV
          </Button>
        }
      />

      {/* Compliance stats */}
      <div className="mb-8 grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3">
        <KpiCard
          label="Licensed vehicles"
          value={stats.data?.total_licensed_vehicles.toLocaleString() ?? '—'}
          icon={ShieldCheck}
          loading={stats.isLoading}
        />
        <KpiCard
          label="Trips this month"
          value={stats.data?.total_trips_this_month.toLocaleString() ?? '—'}
          icon={ShieldCheck}
          loading={stats.isLoading}
        />
        <KpiCard
          label="Compliance rate"
          value={
            stats.data?.reporting_compliance_rate
              ? `${(stats.data.reporting_compliance_rate * 100).toFixed(1)}%`
              : '—'
          }
          icon={ShieldCheck}
          loading={stats.isLoading}
        />
      </div>

      {/* Trip report */}
      <Card>
        <CardHeader>
          <CardTitle>Trip report</CardTitle>
          <CardDescription>
            Completed trips in the selected date range. This is the exact data
            submitted to LATRA's monitoring API.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-6">
          <div className="flex flex-wrap items-end gap-4">
            <div>
              <Label htmlFor="start-date">Start date</Label>
              <Input
                id="start-date"
                type="date"
                value={startDate}
                onChange={(e) => setStartDate(e.target.value)}
                className="w-44"
              />
            </div>
            <div>
              <Label htmlFor="end-date">End date</Label>
              <Input
                id="end-date"
                type="date"
                value={endDate}
                onChange={(e) => setEndDate(e.target.value)}
                className="w-44"
              />
            </div>
          </div>

          <DataTable
            columns={columns}
            data={trips.data?.trips ?? []}
            loading={trips.isLoading}
            emptyMessage="No trips in this date range"
          />
        </CardContent>
      </Card>
    </>
  );
}
