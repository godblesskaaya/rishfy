import { ArrowDownRight, ArrowUpRight } from 'lucide-react';

import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';

interface KpiCardProps {
  label: string;
  value: string | number;
  delta?: number;
  deltaSuffix?: string;
  icon: React.ComponentType<{ className?: string }>;
  loading?: boolean;
}

export function KpiCard({
  label,
  value,
  delta,
  deltaSuffix = 'vs last week',
  icon: Icon,
  loading = false,
}: KpiCardProps) {
  const hasDelta = delta !== undefined && delta !== null;
  const positive = hasDelta && delta >= 0;

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium text-muted-foreground">
          {label}
        </CardTitle>
        <Icon className="h-4 w-4 text-muted-foreground" />
      </CardHeader>
      <CardContent>
        {loading ? (
          <>
            <Skeleton className="mb-2 h-8 w-24" />
            <Skeleton className="h-4 w-32" />
          </>
        ) : (
          <>
            <div className="text-2xl font-bold">{value}</div>
            {hasDelta && (
              <p
                className={cn(
                  'mt-1 flex items-center gap-1 text-xs',
                  positive ? 'text-success' : 'text-destructive',
                )}
              >
                {positive ? (
                  <ArrowUpRight className="h-3 w-3" />
                ) : (
                  <ArrowDownRight className="h-3 w-3" />
                )}
                <span className="font-medium">
                  {positive ? '+' : ''}
                  {delta.toFixed(1)}%
                </span>
                <span className="text-muted-foreground">{deltaSuffix}</span>
              </p>
            )}
          </>
        )}
      </CardContent>
    </Card>
  );
}
