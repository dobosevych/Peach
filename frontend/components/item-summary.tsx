"use client"

import { useQuery } from "@tanstack/react-query"

import { Skeleton } from "@/components/ui/skeleton"
import { api } from "@/lib/api"

export function ItemSummary() {
  const { data, isPending, isError } = useQuery({
    queryKey: ["items"],
    queryFn: () => api.listItems({ limit: 100 }),
  })

  if (isPending) return <Skeleton className="h-11 w-40 rounded-md" />
  if (isError) return <p className="text-sm text-muted-foreground">Unavailable</p>

  const done = data.items.filter((item) => item.is_done).length

  return (
    <div className="flex items-baseline gap-8">
      <div>
        <p className="font-heading text-[2rem] leading-none font-bold tabular-nums">
          {data.total}
        </p>
        <p className="mt-1.5 text-xs font-medium tracking-wide text-muted-foreground uppercase">
          total
        </p>
      </div>
      <div>
        <p className="font-heading text-[2rem] leading-none font-bold tabular-nums">
          {done}
        </p>
        <p className="mt-1.5 text-xs font-medium tracking-wide text-muted-foreground uppercase">
          done
        </p>
      </div>
    </div>
  )
}
