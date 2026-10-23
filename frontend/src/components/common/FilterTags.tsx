import { cn } from 'cn'

export interface FilterTagsOption<T extends string> {
  value: T | ''
  label: string
}

interface FilterTagsProps<T extends string> {
  /** Accessible group label. */
  label: string
  options: FilterTagsOption<T>[]
  value: T | ''
  onChange: (value: T | '') => void
  className?: string
}

/**
 * Accessible single-select filter rendered as a row of selectable tags.
 * Implemented as a radio group so keyboard and screen-reader users get the
 * same single-choice semantics the previous <select> provided.
 */
export function FilterTags<T extends string>({
  label,
  options,
  value,
  onChange,
  className,
}: FilterTagsProps<T>) {
  return (
    <div className={cn('flex flex-col gap-1.5', className)}>
      <span className="text-sm font-medium">{label}</span>
      <div role="radiogroup" aria-label={label} className="flex flex-wrap gap-1.5">
        {options.map((opt) => {
          const selected = opt.value === value
          return (
            <button
              key={opt.value || '__all__'}
              type="button"
              role="radio"
              aria-checked={selected}
              onClick={() => onChange(opt.value)}
              className={cn(
                'fx-tada inline-flex h-7 items-center rounded-full border px-3 text-sm transition-all duration-200 ease-out',
                'hover:-translate-y-1 hover:scale-110 active:scale-90',
                'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/50',
                selected
                  ? 'border-transparent bg-primary text-primary-foreground shadow-float animate-rainbow-glow'
                  : 'border-border bg-background text-foreground hover:border-primary/40 hover:bg-muted',
              )}
            >
              {opt.label}
            </button>
          )
        })}
      </div>
    </div>
  )
}
