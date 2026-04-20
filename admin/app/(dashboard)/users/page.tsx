'use client';

import { useQuery } from '@tanstack/react-query';
import type { ColumnDef } from '@tanstack/react-table';
import { ArrowUpDown } from 'lucide-react';
import { useState } from 'react';

import { DataTable } from '@/components/data-table/data-table';
import { PageHeader } from '@/components/layout/page-header';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { usersApi } from '@/lib/api/endpoints';
import { formatDate, maskPhone } from '@/lib/utils';
import type { User } from '@/types/api';

const columns: ColumnDef<User>[] = [
  {
    accessorKey: 'first_name',
    header: ({ column }) => (
      <Button
        variant="ghost"
        size="sm"
        className="-ml-3"
        onClick={() => column.toggleSorting(column.getIsSorted() === 'asc')}
      >
        Name
        <ArrowUpDown className="ml-2 h-3 w-3" />
      </Button>
    ),
    cell: ({ row }) => (
      <div>
        <div className="font-medium">
          {row.original.first_name} {row.original.last_name}
        </div>
        <div className="text-xs text-muted-foreground">
          {maskPhone(row.original.phone_number)}
        </div>
      </div>
    ),
  },
  {
    accessorKey: 'role',
    header: 'Role',
    cell: ({ row }) => (
      <Badge variant="outline" className="capitalize">
        {row.original.role}
      </Badge>
    ),
  },
  {
    accessorKey: 'status',
    header: 'Status',
    cell: ({ row }) => (
      <Badge
        variant={row.original.status === 'active' ? 'success' : 'destructive'}
        className="capitalize"
      >
        {row.original.status}
      </Badge>
    ),
  },
  {
    accessorKey: 'rating_average',
    header: 'Rating',
    cell: ({ row }) =>
      row.original.rating_count > 0
        ? `★ ${row.original.rating_average.toFixed(1)} (${row.original.rating_count})`
        : '—',
  },
  {
    accessorKey: 'created_at',
    header: 'Joined',
    cell: ({ row }) => formatDate(row.original.created_at),
  },
];

export default function UsersPage() {
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);

  const { data, isLoading } = useQuery({
    queryKey: ['users', page, search],
    queryFn: () => usersApi.list({ page, page_size: 20, search }),
  });

  return (
    <>
      <PageHeader
        title="Users"
        description={`${data?.pagination.total_count ?? 0} total users`}
      />

      <div className="mb-4">
        <Input
          placeholder="Search by name or phone..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="max-w-sm"
        />
      </div>

      <DataTable
        columns={columns}
        data={data?.items ?? []}
        loading={isLoading}
        emptyMessage="No users found"
      />
    </>
  );
}
