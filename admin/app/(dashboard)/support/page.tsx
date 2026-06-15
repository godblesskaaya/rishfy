'use client';

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import type { ColumnDef } from '@tanstack/react-table';
import { Check, MessageSquareReply, X } from 'lucide-react';

import { DataTable } from '@/components/data-table/data-table';
import { PageHeader } from '@/components/layout/page-header';
import { StatusBadge } from '@/components/status-badge';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { supportApi } from '@/lib/api/endpoints';
import { formatDateTime } from '@/lib/utils';
import type { SupportCase } from '@/types/api';

export default function SupportPage() {
  const queryClient = useQueryClient();
  const { data, isLoading } = useQuery({
    queryKey: ['support-cases'],
    queryFn: () => supportApi.listCases({ limit: 50, offset: 0 }),
  });

  const refresh = async () => {
    await queryClient.invalidateQueries({ queryKey: ['support-cases'] });
  };
  const updateCase = useMutation({
    mutationFn: ({
      caseId,
      body,
    }: {
      caseId: string;
      body: Parameters<typeof supportApi.updateCase>[1];
    }) => supportApi.updateCase(caseId, body),
    onSuccess: refresh,
  });

  const columns: ColumnDef<SupportCase>[] = [
    {
      accessorKey: 'priority',
      header: 'Priority',
      cell: ({ row }) => (
        <Badge variant={row.original.priority === 'urgent' ? 'destructive' : 'outline'}>
          {row.original.priority}
        </Badge>
      ),
    },
    {
      accessorKey: 'subject',
      header: 'Case',
      cell: ({ row }) => (
        <div className="max-w-xl">
          <div className="font-medium">{row.original.subject}</div>
          <div className="line-clamp-2 text-xs text-muted-foreground">
            {row.original.message}
          </div>
        </div>
      ),
    },
    {
      accessorKey: 'category',
      header: 'Category',
      cell: ({ row }) => row.original.category.replaceAll('_', ' '),
    },
    {
      accessorKey: 'status',
      header: 'Status',
      cell: ({ row }) => <StatusBadge status={row.original.status} />,
    },
    {
      accessorKey: 'user_id',
      header: 'User',
      cell: ({ row }) => <span className="font-mono text-xs">{row.original.user_id}</span>,
    },
    {
      accessorKey: 'booking_id',
      header: 'Booking',
      cell: ({ row }) => (
        <span className="font-mono text-xs">{row.original.booking_id ?? '-'}</span>
      ),
    },
    {
      accessorKey: 'created_at',
      header: 'Created',
      cell: ({ row }) => formatDateTime(row.original.created_at),
    },
    {
      id: 'actions',
      header: 'Actions',
      cell: ({ row }) => {
        const item = row.original;
        return (
          <div className="flex flex-wrap gap-2">
            {item.status === 'open' && (
              <Button
                size="sm"
                variant="outline"
                onClick={() =>
                  updateCase.mutate({
                    caseId: item.id,
                    body: { status: 'waiting', support_responded: true },
                  })
                }
              >
                <MessageSquareReply className="mr-1 h-4 w-4" />
                Responded
              </Button>
            )}
            {!['resolved', 'closed'].includes(item.status) && (
              <Button
                size="sm"
                variant="outline"
                onClick={() =>
                  updateCase.mutate({ caseId: item.id, body: { status: 'resolved' } })
                }
              >
                <Check className="mr-1 h-4 w-4" />
                Resolve
              </Button>
            )}
            {item.status !== 'closed' && (
              <Button
                size="sm"
                variant="ghost"
                onClick={() =>
                  updateCase.mutate({ caseId: item.id, body: { status: 'closed' } })
                }
              >
                <X className="mr-1 h-4 w-4" />
                Close
              </Button>
            )}
          </div>
        );
      },
    },
  ];

  return (
    <>
      <PageHeader title="Support" description="User support case queue" />
      <DataTable
        columns={columns}
        data={data?.cases ?? []}
        loading={isLoading}
        emptyMessage="No support cases"
      />
    </>
  );
}
