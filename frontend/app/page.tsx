import Link from "next/link"

import { HealthBadge } from "@/components/health-badge"
import { ItemSummary } from "@/components/item-summary"
import { Button } from "@/components/ui/button"
import {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"

export default function DashboardPage() {
  return (
    <div className="grid gap-6">
      <div>
        <h1 className="font-heading text-3xl font-semibold tracking-tight">Dashboard</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Placeholder screens. They exist to prove the browser, API and database talk to
          each other.
        </p>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>API</CardTitle>
            <CardDescription>Readiness of the backend and its database</CardDescription>
            <CardAction>
              <HealthBadge />
            </CardAction>
          </CardHeader>
          <CardContent className="text-sm text-muted-foreground">
            Polled every 15 seconds from <code>/api/v1/health/ready</code>.
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Items</CardTitle>
            <CardDescription>The placeholder resource</CardDescription>
          </CardHeader>
          <CardContent className="grid gap-4">
            <ItemSummary />
            <Button asChild variant="outline" className="justify-self-start">
              <Link href="/items">Manage items</Link>
            </Button>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
