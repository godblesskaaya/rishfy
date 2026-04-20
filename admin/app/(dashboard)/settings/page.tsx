'use client';

import { useSession } from 'next-auth/react';

import { PageHeader } from '@/components/layout/page-header';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { Label } from '@/components/ui/label';
import { Separator } from '@/components/ui/separator';

export default function SettingsPage() {
  const { data: session } = useSession();

  return (
    <>
      <PageHeader
        title="Settings"
        description="Your account and platform configuration"
      />

      <div className="space-y-6">
        <Card>
          <CardHeader>
            <CardTitle>Your account</CardTitle>
            <CardDescription>Information tied to your admin profile</CardDescription>
          </CardHeader>
          <CardContent className="grid gap-4 md:grid-cols-2">
            <div>
              <Label>Name</Label>
              <p className="text-sm">{session?.user.name ?? '—'}</p>
            </div>
            <div>
              <Label>Email</Label>
              <p className="text-sm">{session?.user.email ?? '—'}</p>
            </div>
            <div>
              <Label>Role</Label>
              <p className="text-sm capitalize">{session?.user.role ?? '—'}</p>
            </div>
            <div>
              <Label>User ID</Label>
              <p className="font-mono text-xs">{session?.user.id ?? '—'}</p>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Platform configuration</CardTitle>
            <CardDescription>
              Business rules and operational parameters (read-only)
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <ConfigRow label="Platform fee" value="15%" />
            <Separator />
            <ConfigRow
              label="Free cancellation window"
              value="2 hours before departure"
            />
            <Separator />
            <ConfigRow label="Location sampling interval" value="30 seconds" />
            <Separator />
            <ConfigRow label="Max seats per booking" value="6" />
            <Separator />
            <ConfigRow label="Location retention" value="90 days" />
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Permissions</CardTitle>
            <CardDescription>Capabilities granted to your account</CardDescription>
          </CardHeader>
          <CardContent>
            <div className="flex flex-wrap gap-2">
              {session?.user.permissions.map((perm) => (
                <code
                  key={perm}
                  className="rounded bg-muted px-2 py-1 text-xs"
                >
                  {perm}
                </code>
              ))}
              {(!session?.user.permissions ||
                session.user.permissions.length === 0) && (
                <p className="text-sm text-muted-foreground">
                  No explicit permissions assigned (using role defaults)
                </p>
              )}
            </div>
          </CardContent>
        </Card>
      </div>
    </>
  );
}

function ConfigRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between">
      <p className="text-sm font-medium">{label}</p>
      <p className="text-sm text-muted-foreground">{value}</p>
    </div>
  );
}
