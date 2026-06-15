'use client';

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import type { ColumnDef } from '@tanstack/react-table';
import { Check, EyeOff } from 'lucide-react';

import { DataTable } from '@/components/data-table/data-table';
import { PageHeader } from '@/components/layout/page-header';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { moderationApi } from '@/lib/api/endpoints';
import { formatDateTime } from '@/lib/utils';
import type { ModeratedReview } from '@/types/api';

export default function ModerationPage() {
  const queryClient = useQueryClient();
  const { data, isLoading } = useQuery({
    queryKey: ['moderation', 'reviews'],
    queryFn: () => moderationApi.listReviews({ status: 'pending', limit: 50, offset: 0 }),
  });

  const moderate = useMutation({
    mutationFn: ({
      ratingId,
      status,
      hiddenReason,
    }: {
      ratingId: string;
      status: 'approved' | 'hidden';
      hiddenReason?: string;
    }) =>
      moderationApi.moderateReview(ratingId, {
        status,
        hidden_reason: hiddenReason,
      }),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['moderation', 'reviews'] });
    },
  });

  const columns: ColumnDef<ModeratedReview>[] = [
    {
      accessorKey: 'score',
      header: 'Score',
      cell: ({ row }) => (
        <Badge variant={row.original.score <= 2 ? 'destructive' : 'outline'}>
          {row.original.score}
        </Badge>
      ),
    },
    {
      accessorKey: 'comment',
      header: 'Review',
      cell: ({ row }) => row.original.comment ?? '-',
    },
    {
      accessorKey: 'booking_id',
      header: 'Booking',
      cell: ({ row }) => <span className="font-mono text-xs">{row.original.booking_id}</span>,
    },
    {
      accessorKey: 'ratee_id',
      header: 'Ratee',
      cell: ({ row }) => <span className="font-mono text-xs">{row.original.ratee_id}</span>,
    },
    {
      accessorKey: 'created_at',
      header: 'Submitted',
      cell: ({ row }) => formatDateTime(row.original.created_at),
    },
    {
      id: 'actions',
      header: 'Actions',
      cell: ({ row }) => (
        <div className="flex flex-wrap gap-2">
          <Button
            size="sm"
            variant="outline"
            onClick={() => moderate.mutate({ ratingId: row.original.id, status: 'approved' })}
          >
            <Check className="mr-1 h-4 w-4" />
            Approve
          </Button>
          <Button
            size="sm"
            variant="ghost"
            onClick={() => {
              const hiddenReason = window.prompt('Hidden reason');
              if (hiddenReason) {
                moderate.mutate({ ratingId: row.original.id, status: 'hidden', hiddenReason });
              }
            }}
          >
            <EyeOff className="mr-1 h-4 w-4" />
            Hide
          </Button>
        </div>
      ),
    },
  ];

  return (
    <>
      <PageHeader title="Moderation" description="Pending review queue" />
      <DataTable
        columns={columns}
        data={data?.reviews ?? []}
        loading={isLoading}
        emptyMessage="No pending reviews"
      />
    </>
  );
}
