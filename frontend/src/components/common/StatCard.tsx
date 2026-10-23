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
  /** Stagger index for the entrance cascade. */
  index?: number
  className?: string
}

export function StatCard({
  label,
  value,
  icon: Icon,
  tone = 'primary',
  hint,
  index = 0,
  className,
}: StatCardProps) {
  return (
    <div
      style={{ ['--i' as string]: index }}
      className={cn(
        'group fx-jello hover:animate-rainbow-glow relative flex items-start justify-between gap-3 overflow-hidden rounded-2xl bg-card p-5 shadow-card ring-1 ring-foreground/5 transition-all',
        'animate-bounce-in cursor-pointer',
        className,
      )}
    >
      {/* Subtle tone glow that intensifies on hover. */}
      <span
        aria-hidden
        className={cn(
          'pointer-events-none absolute -right-8 -top-8 size-24 rounded-full opacity-0 blur-2xl transition-opacity duration-300 group-hover:opacity-80',
          TONE[tone],
        )}
      />
      <div className="relative min-w-0 space-y-1">
        <p className="text-sm font-medium text-muted-foreground">{label}</p>
        <p className="font-heading text-3xl font-semibold tracking-tight tabular-nums transition-transform duration-300 group-hover:scale-110">
          {value}
        </p>
        {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
      </div>
      {Icon && (
        <span
          className={cn(
            'fx-spin-on-hover relative flex size-11 shrink-0 items-center justify-center rounded-xl transition-transform duration-300 group-hover:scale-125 group-hover:-rotate-12',
            TONE[tone],
          )}
        >
          <Icon className="size-5" />
        </span>
      )}
    </div>
  )
}
