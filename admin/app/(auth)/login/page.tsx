'use client';

import { zodResolver } from '@hookform/resolvers/zod';
import { Car, Loader2 } from 'lucide-react';
import { signIn } from 'next-auth/react';
import { useRouter, useSearchParams } from 'next/navigation';
import { useState } from 'react';
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
  phoneNumber: z
    .string()
    .min(10, 'Phone number is required')
    .regex(/^\+?[0-9]{10,15}$/, 'Invalid phone number format'),
  password: z.string().min(8, 'Password must be at least 8 characters'),
});

type LoginForm = z.infer<typeof loginSchema>;

export default function LoginPage() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const callbackUrl = searchParams.get('callbackUrl') ?? '/overview';
  const [submitting, setSubmitting] = useState(false);

  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<LoginForm>({
    resolver: zodResolver(loginSchema),
    defaultValues: { phoneNumber: '+255', password: '' },
  });

  async function onSubmit(data: LoginForm) {
    setSubmitting(true);
    try {
      const result = await signIn('credentials', {
        phoneNumber: data.phoneNumber,
        password: data.password,
        redirect: false,
      });

      if (result?.error) {
        toast.error('Invalid credentials', {
          description: 'Please check your phone number and password.',
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
                <Label htmlFor="phoneNumber">Phone number</Label>
                <Input
                  id="phoneNumber"
                  type="tel"
                  placeholder="+255 712 345 678"
                  autoComplete="username"
                  {...register('phoneNumber')}
                />
                {errors.phoneNumber && (
                  <p className="text-sm text-destructive">
                    {errors.phoneNumber.message}
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
