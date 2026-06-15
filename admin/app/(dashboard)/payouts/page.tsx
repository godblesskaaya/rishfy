'use client';

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import type { ColumnDef } from '@tanstack/react-table';
import { Check, X, BadgeCheck } from 'lucide-react';

import { DataTable } from '@/components/data-table/data-table';
import { PageHeader } from '@/components/layout/page-header';
import { StatusBadge } from '@/components/status-badge';
import { Button } from '@/components/ui/button';
import { payoutsApi } from '@/lib/api/endpoints';
import { formatDateTime, formatTZS, maskPhone } from '@/lib/utils';
import type { Payout } from '@/types/api';

export default function PayoutsPage() {
  const queryClient = useQueryClient();
  const { data, isLoading } = useQuery({
    queryKey: ['payouts'],
    queryFn: () => payoutsApi.list({ page: 1, page_size: 50 }),
  });

  const refresh = async () => {
    await queryClient.invalidateQueries({ queryKey: ['payouts'] });
  };
  const approve = useMutation({ mutationFn: payoutsApi.approve, onSuccess: refresh });
  const fail = useMutation({
    mutationFn: ({ payoutId, reason }: { payoutId: string; reason: string }) =>
      payoutsApi.fail(payoutId, reason),
    onSuccess: refresh,
  });
  const complete = useMutation({
    mutationFn: ({ payoutId, reference }: { payoutId: string; reference: string }) =>
      payoutsApi.complete(payoutId, reference),
    onSuccess: refresh,
  });

  const columns: ColumnDef<Payout>[] = [
    {
      accessorKey: 'payoutId',
      header: 'Payout',
      cell: ({ row }) => <span className="font-mono text-xs">{row.original.payoutId}</span>,
    },
    {
      accessorKey: 'driverUserId',
      header: 'Driver',
      cell: ({ row }) => <span className="font-mono text-xs">{row.original.driverUserId}</span>,
    },
    {
      accessorKey: 'amountTzs',
      header: 'Amount',
      cell: ({ row }) => formatTZS(row.original.amountTzs),
    },
    {
      accessorKey: 'status',
      header: 'Status',
      cell: ({ row }) => <StatusBadge status={row.original.status} />,
    },
    {
      accessorKey: 'payoutPhone',
      header: 'Destination',
      cell: ({ row }) => (
        <div>
          <div>{row.original.payoutMethod}</div>
          <div className="text-xs text-muted-foreground">{maskPhone(row.original.payoutPhone)}</div>
        </div>
      ),
    },
    {
      accessorKey: 'requestedAt',
      header: 'Requested',
      cell: ({ row }) => formatDateTime(row.original.requestedAt),
    },
    {
      id: 'actions',
      header: 'Actions',
      cell: ({ row }) => {
        const payout = row.original;
        return (
          <div className="flex flex-wrap gap-2">
            {payout.status === 'pending_review' && (
              <Button size="sm" variant="outline" onClick={() => approve.mutate(payout.payoutId)}>
                <Check className="mr-1 h-4 w-4" />
                Approve
              </Button>
            )}
            {payout.status === 'processing' && (
              <Button
                size="sm"
                variant="outline"
                onClick={() => {
                  const reference = window.prompt('Provider reference');
                  if (reference) complete.mutate({ payoutId: payout.payoutId, reference });
                }}
              >
                <BadgeCheck className="mr-1 h-4 w-4" />
                Complete
              </Button>
            )}
            {['pending_review', 'processing'].includes(payout.status) && (
              <Button
                size="sm"
                variant="ghost"
                onClick={() => {
                  const reason = window.prompt('Failure reason') ?? 'Manual failure';
                  fail.mutate({ payoutId: payout.payoutId, reason });
                }}
              >
                <X className="mr-1 h-4 w-4" />
                Fail
              </Button>
            )}
          </div>
        );
      },
    },
  ];

  return (
    <>
      <PageHeader title="Payouts" description="Driver payout review and settlement state" />
      <DataTable columns={columns} data={data?.items ?? []} loading={isLoading} />
    </>
  );
}
