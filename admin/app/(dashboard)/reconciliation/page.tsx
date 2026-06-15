'use client';

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import type { ColumnDef } from '@tanstack/react-table';
import { Upload } from 'lucide-react';
import { useState } from 'react';

import { DataTable } from '@/components/data-table/data-table';
import { PageHeader } from '@/components/layout/page-header';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { reconciliationApi } from '@/lib/api/endpoints';
import { formatDateTime, formatTZS } from '@/lib/utils';
import type { ReconciliationRecord } from '@/types/api';

const columns: ColumnDef<ReconciliationRecord>[] = [
  {
    accessorKey: 'providerReference',
    header: 'Provider Reference',
    cell: ({ row }) => <span className="font-mono text-xs">{row.original.providerReference}</span>,
  },
  {
    accessorKey: 'provider',
    header: 'Provider',
  },
  {
    accessorKey: 'amountTzs',
    header: 'Amount',
    cell: ({ row }) => formatTZS(row.original.amountTzs),
  },
  {
    accessorKey: 'providerStatus',
    header: 'Provider Status',
  },
  {
    accessorKey: 'matchStatus',
    header: 'Match',
    cell: ({ row }) => (
      <Badge variant={row.original.matchStatus === 'matched' ? 'success' : 'destructive'}>
        {row.original.matchStatus}
      </Badge>
    ),
  },
  {
    accessorKey: 'mismatchReason',
    header: 'Reason',
    cell: ({ row }) => row.original.mismatchReason ?? '-',
  },
  {
    accessorKey: 'importedAt',
    header: 'Imported',
    cell: ({ row }) => formatDateTime(row.original.importedAt),
  },
];

export default function ReconciliationPage() {
  const queryClient = useQueryClient();
  const [recordsJson, setRecordsJson] = useState('');
  const { data, isLoading } = useQuery({
    queryKey: ['reconciliation', 'provider-payments'],
    queryFn: () => reconciliationApi.listPayments({ limit: 50, offset: 0 }),
  });

  const importMutation = useMutation({
    mutationFn: async () => {
      const parsed = JSON.parse(recordsJson) as Parameters<typeof reconciliationApi.importPayments>[0];
      return reconciliationApi.importPayments(parsed);
    },
    onSuccess: async () => {
      setRecordsJson('');
      await queryClient.invalidateQueries({ queryKey: ['reconciliation', 'provider-payments'] });
    },
  });

  return (
    <>
      <PageHeader title="Reconciliation" description="Provider payment import and mismatch review" />

      <div className="mb-4 grid gap-3 lg:grid-cols-[1fr_auto]">
        <textarea
          value={recordsJson}
          onChange={(event) => setRecordsJson(event.target.value)}
          placeholder='[{"provider":"azampay","providerReference":"TX-1","amountTzs":10000,"providerStatus":"completed"}]'
          className="min-h-24 rounded-md border bg-background px-3 py-2 text-sm font-mono"
        />
        <Button
          className="self-start"
          disabled={!recordsJson.trim() || importMutation.isPending}
          onClick={() => importMutation.mutate()}
        >
          <Upload className="mr-2 h-4 w-4" />
          Import
        </Button>
      </div>

      <DataTable columns={columns} data={data?.items ?? []} loading={isLoading} />
    </>
  );
}
