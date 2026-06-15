'use client';

import { zodResolver } from '@hookform/resolvers/zod';
import { Car, Loader2 } from 'lucide-react';
import type { Route } from 'next';
import { signIn } from 'next-auth/react';
import { useRouter, useSearchParams } from 'next/navigation';
import { Suspense, useState } from 'react';
import { useForm } from 'react-hook-form';
import { toast } from 'sonner';
import { z } from 'zod';

import { Button } from '@/components/ui/button';
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';

const loginSchema = z.object({
  identifier: z
    .string()
    .min(5, 'Email or phone number is required')
    .refine(
      (value) => value.includes('@') || /^\+?[0-9]{10,15}$/.test(value),
      'Enter a valid email or phone number',
    ),
  password: z.string().min(8, 'Password must be at least 8 characters'),
});

type LoginForm = z.infer<typeof loginSchema>;

function getSafeCallbackUrl(callbackUrl: string | null): Route {
  if (!callbackUrl || !callbackUrl.startsWith('/') || callbackUrl.startsWith('//')) {
    return '/overview';
  }

  return callbackUrl as Route;
}

function LoginPageContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const callbackUrl = getSafeCallbackUrl(searchParams.get('callbackUrl'));
  const [submitting, setSubmitting] = useState(false);

  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<LoginForm>({
    resolver: zodResolver(loginSchema),
    defaultValues: { identifier: '', password: '' },
  });

  async function onSubmit(data: LoginForm) {
    setSubmitting(true);
    try {
      const result = await signIn('credentials', {
        identifier: data.identifier,
        password: data.password,
        redirect: false,
      });

      if (result?.error) {
        toast.error('Invalid credentials', {
          description: 'Please check your email or phone number and password.',
        });
        return;
      }

      toast.success('Welcome back');
      router.push(callbackUrl);
      router.refresh();
    } catch (error) {
      toast.error('Login failed', {
        description: 'Something went wrong. Please try again.',
      });
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-background via-background to-primary/10 p-4">
      <div className="w-full max-w-md">
        <div className="mb-8 flex items-center justify-center gap-2">
          <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-primary text-primary-foreground">
            <Car className="h-6 w-6" />
          </div>
          <div>
            <h1 className="text-2xl font-bold">Rishfy</h1>
            <p className="text-xs text-muted-foreground">Admin Console</p>
          </div>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>Sign in</CardTitle>
            <CardDescription>
              Access the Rishfy admin dashboard
            </CardDescription>
          </CardHeader>
          <form onSubmit={handleSubmit(onSubmit)}>
            <CardContent className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="identifier">Email or phone number</Label>
                <Input
                  id="identifier"
                  type="text"
                  placeholder="admin@rishfy.co.tz or +255700000001"
                  autoComplete="username"
                  {...register('identifier')}
                />
                {errors.identifier && (
                  <p className="text-sm text-destructive">
                    {errors.identifier.message}
                  </p>
                )}
              </div>

              <div className="space-y-2">
                <Label htmlFor="password">Password</Label>
                <Input
                  id="password"
                  type="password"
                  autoComplete="current-password"
                  {...register('password')}
                />
                {errors.password && (
                  <p className="text-sm text-destructive">
                    {errors.password.message}
                  </p>
                )}
              </div>
            </CardContent>
            <CardFooter className="flex flex-col gap-3">
              <Button type="submit" className="w-full" disabled={submitting}>
                {submitting && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                Sign in
              </Button>
              <p className="text-center text-xs text-muted-foreground">
                Admin access only. Contact your administrator if you need help.
              </p>
            </CardFooter>
          </form>
        </Card>
      </div>
    </div>
  );
}

export default function LoginPage() {
  return (
    <Suspense fallback={null}>
      <LoginPageContent />
    </Suspense>
  );
}
