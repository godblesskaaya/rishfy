'use client';

import { useQuery } from '@tanstack/react-query';
import type { ColumnDef } from '@tanstack/react-table';

import { DataTable } from '@/components/data-table/data-table';
import { PageHeader } from '@/components/layout/page-header';
import { StatusBadge } from '@/components/status-badge';
import { Badge } from '@/components/ui/badge';
import { paymentsApi } from '@/lib/api/endpoints';
import { formatDateTime, formatTZS, maskPhone } from '@/lib/utils';
import type { Payment } from '@/types/api';

const methodLabels: Record<string, string> = {
  mpesa: 'M-Pesa',
  tigopesa: 'TigoPesa',
  airtel_money: 'Airtel Money',
  cash: 'Cash',
};

const columns: ColumnDef<Payment>[] = [
  {
    accessorKey: 'internal_reference',
    header: 'Reference',
    cell: ({ row }) => (
      <span className="font-mono text-xs">{row.original.internal_reference}</span>
    ),
  },
  {
    accessorKey: 'user_name',
    header: 'Payer',
    cell: ({ row }) => (
      <div>
        <div>{row.original.user_name ?? '—'}</div>
        <div className="text-xs text-muted-foreground">
          {maskPhone(row.original.payer_phone)}
        </div>
      </div>
    ),
  },
  {
    accessorKey: 'method',
    header: 'Method',
    cell: ({ row }) => (
      <Badge variant="outline">{methodLabels[row.original.method] ?? row.original.method}</Badge>
    ),
  },
  {
    accessorKey: 'amount',
    header: 'Amount',
    cell: ({ row }) => formatTZS(row.original.amount),
  },
  {
    accessorKey: 'status',
    header: 'Status',
    cell: ({ row }) => <StatusBadge status={row.original.status} />,
  },
  {
    accessorKey: 'completed_at',
    header: 'Completed',
    cell: ({ row }) => formatDateTime(row.original.completed_at),
  },
];

export default function PaymentsPage() {
  const { data, isLoading } = useQuery({
    queryKey: ['payments'],
    queryFn: () => paymentsApi.list({ page: 1, page_size: 50 }),
  });

  return (
    <>
      <PageHeader title="Payments" description="All platform transactions" />
      <DataTable columns={columns} data={data?.items ?? []} loading={isLoading} />
    </>
  );
}
