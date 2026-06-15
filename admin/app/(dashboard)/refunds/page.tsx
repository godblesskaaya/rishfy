'use client';

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import type { ColumnDef } from '@tanstack/react-table';
import { BadgeCheck } from 'lucide-react';

import { DataTable } from '@/components/data-table/data-table';
import { PageHeader } from '@/components/layout/page-header';
import { StatusBadge } from '@/components/status-badge';
import { Button } from '@/components/ui/button';
import { refundsApi } from '@/lib/api/endpoints';
import { formatDateTime, formatTZS } from '@/lib/utils';
import type { Refund } from '@/types/api';

export default function RefundsPage() {
  const queryClient = useQueryClient();
  const { data, isLoading } = useQuery({
    queryKey: ['refunds'],
    queryFn: () => refundsApi.list({ page: 1, page_size: 50 }),
  });

  const complete = useMutation({
    mutationFn: ({ refundId, reference }: { refundId: string; reference: string }) =>
      refundsApi.complete(refundId, reference),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['refunds'] });
    },
  });

  const columns: ColumnDef<Refund>[] = [
    {
      accessorKey: 'refund_id',
      header: 'Refund',
      cell: ({ row }) => <span className="font-mono text-xs">{row.original.refund_id}</span>,
    },
    {
      accessorKey: 'payment_id',
      header: 'Payment',
      cell: ({ row }) => <span className="font-mono text-xs">{row.original.payment_id}</span>,
    },
    {
      accessorKey: 'amount_tzs',
      header: 'Amount',
      cell: ({ row }) => formatTZS(row.original.amount_tzs),
    },
    {
      accessorKey: 'status',
      header: 'Status',
      cell: ({ row }) => <StatusBadge status={row.original.status} />,
    },
    {
      accessorKey: 'policy',
      header: 'Policy',
      cell: ({ row }) => row.original.policy.replaceAll('_', ' '),
    },
    {
      accessorKey: 'failure_reason',
      header: 'Failure',
      cell: ({ row }) => row.original.failure_reason ?? '-',
    },
    {
      accessorKey: 'requested_at',
      header: 'Requested',
      cell: ({ row }) => formatDateTime(row.original.requested_at),
    },
    {
      id: 'actions',
      header: 'Actions',
      cell: ({ row }) => {
        const refund = row.original;
        if (refund.status !== 'manual_required') return null;
        return (
          <Button
            size="sm"
            variant="outline"
            onClick={() => {
              const reference = window.prompt('Manual refund reference');
              if (reference) complete.mutate({ refundId: refund.refund_id, reference });
            }}
          >
            <BadgeCheck className="mr-1 h-4 w-4" />
            Complete
          </Button>
        );
      },
    },
  ];

  return (
    <>
      <PageHeader title="Refunds" description="Manual and automated refund operations" />
      <DataTable columns={columns} data={data?.items ?? []} loading={isLoading} />
    </>
  );
}
