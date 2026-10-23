/** Accessible required-field marker: a visible asterisk with a screen-reader label. */
export function RequiredMark() {
  return (
    <span className="text-destructive" title="Champ obligatoire">
      <span aria-hidden="true"> *</span>
      <span className="sr-only"> (obligatoire)</span>
    </span>
  )
}
