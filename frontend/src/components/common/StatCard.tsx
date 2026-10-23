import type { LucideIcon } from 'lucide-react'
import { cn } from 'cn'

type Tone = 'primary' | 'success' | 'warning' | 'destructive' | 'neutral'

const TONE: Record<Tone, string> = {
  primary: 'bg-primary/10 text-primary',
  success: 'bg-success/15 text-success',
  warning: 'bg-warning/15 text-warning',
  destructive: 'bg-destructive/10 text-destructive',
  neutral: 'bg-muted text-muted-foreground',
}

interface StatCardProps {
  label: string
  value: string | number
  icon?: LucideIcon
  tone?: Tone
  hint?: string
  className?: string
}

export function StatCard({
  label,
  value,
  icon: Icon,
  tone = 'primary',
  hint,
  className,
}: StatCardProps) {
  return (
    <div
      className={cn(
        'flex items-start justify-between gap-3 rounded-2xl bg-card p-5 shadow-card ring-1 ring-foreground/5',
        className,
      )}
    >
      <div className="min-w-0 space-y-1">
        <p className="text-sm font-medium text-muted-foreground">{label}</p>
        <p className="font-heading text-3xl font-semibold tracking-tight">{value}</p>
        {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
      </div>
      {Icon && (
        <span className={cn('flex size-11 shrink-0 items-center justify-center rounded-xl', TONE[tone])}>
          <Icon className="size-5" />
        </span>
      )}
    </div>
  )
}
