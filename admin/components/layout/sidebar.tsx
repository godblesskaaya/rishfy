'use client';

import {
  BarChart3,
  Car,
  CreditCard,
  FileText,
  LayoutDashboard,
  Map,
  Receipt,
  Settings,
  ShieldCheck,
  Users,
} from 'lucide-react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';

import { cn } from '@/lib/utils';

interface NavItem {
  href: string;
  label: string;
  icon: React.ComponentType<{ className?: string }>;
  permissionRequired?: string;
}

const navGroups: Array<{ label: string; items: NavItem[] }> = [
  {
    label: 'Overview',
    items: [
      { href: '/overview', label: 'Dashboard', icon: LayoutDashboard },
    ],
  },
  {
    label: 'Community',
    items: [
      { href: '/users', label: 'Users', icon: Users },
      { href: '/drivers', label: 'Drivers', icon: Car },
      { href: '/vehicles', label: 'Vehicles', icon: Car },
    ],
  },
  {
    label: 'Operations',
    items: [
      { href: '/routes', label: 'Routes', icon: Map },
      { href: '/bookings', label: 'Bookings', icon: Receipt },
      { href: '/payments', label: 'Payments', icon: CreditCard },
    ],
  },
  {
    label: 'Compliance',
    items: [
      { href: '/latra', label: 'LATRA Reports', icon: ShieldCheck },
    ],
  },
  {
    label: 'System',
    items: [
      { href: '/settings', label: 'Settings', icon: Settings },
    ],
  },
];

export function Sidebar() {
  const pathname = usePathname();

  return (
    <aside className="hidden w-64 flex-col border-r bg-card lg:flex">
      {/* Logo */}
      <div className="flex h-16 items-center border-b px-6">
        <Link href="/overview" className="flex items-center gap-2">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary text-primary-foreground">
            <Car className="h-4 w-4" />
          </div>
          <div>
            <p className="text-sm font-semibold">Rishfy</p>
            <p className="text-xs text-muted-foreground">Admin</p>
          </div>
        </Link>
      </div>

      {/* Nav groups */}
      <nav className="flex-1 space-y-6 overflow-y-auto scrollbar-thin px-4 py-6">
        {navGroups.map((group) => (
          <div key={group.label}>
            <p className="mb-2 px-2 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
              {group.label}
            </p>
            <ul className="space-y-1">
              {group.items.map((item) => {
                const isActive =
                  pathname === item.href || pathname.startsWith(`${item.href}/`);
                const Icon = item.icon;
                return (
                  <li key={item.href}>
                    <Link
                      href={item.href as never}
                      className={cn(
                        'flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors',
                        isActive
                          ? 'bg-primary text-primary-foreground'
                          : 'text-muted-foreground hover:bg-accent hover:text-accent-foreground',
                      )}
                    >
                      <Icon className="h-4 w-4" />
                      {item.label}
                    </Link>
                  </li>
                );
              })}
            </ul>
          </div>
        ))}
      </nav>

      {/* Footer */}
      <div className="border-t p-4">
        <p className="text-xs text-muted-foreground">
          v0.1.0 · {process.env.NEXT_PUBLIC_APP_ENV ?? 'development'}
        </p>
      </div>
    </aside>
  );
}
