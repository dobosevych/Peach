"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { MoreHorizontal, Plus } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";

import { ItemFormDialog } from "@/components/item-form-dialog";
import { PageHeader } from "@/components/page-header";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { api, type Item } from "@/lib/api";

export function ItemTable() {
  const queryClient = useQueryClient();
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<Item | null>(null);
  const [pendingDelete, setPendingDelete] = useState<Item | null>(null);

  const { data, isPending, isError, error, refetch } = useQuery({
    queryKey: ["items"],
    queryFn: () => api.listItems({ limit: 100 }),
  });

  const remove = useMutation({
    mutationFn: (item: Item) => api.deleteItem(item.id),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["items"] });
      toast.success("Item deleted");
    },
    onError: (err: Error) => toast.error(err.message),
    onSettled: () => setPendingDelete(null),
  });

  return (
    <div className="grid gap-6">
      <PageHeader
        icon="📋"
        title="Items"
        description={
          data
            ? `${data.total} record${data.total === 1 ? "" : "s"}`
            : "Loading..."
        }
        action={
          <Button
            size="lg"
            onClick={() => {
              setEditing(null);
              setFormOpen(true);
            }}
          >
            <Plus data-icon="inline-start" className="size-4" />
            New item
          </Button>
        }
      />

      {isError && (
        <Alert variant="destructive">
          <AlertTitle>Could not load items</AlertTitle>
          <AlertDescription className="flex items-center gap-4">
            <span>{(error as Error).message}</span>
            <Button size="sm" variant="outline" onClick={() => refetch()}>
              Retry
            </Button>
          </AlertDescription>
        </Alert>
      )}

      {isPending && (
        <div className="grid gap-px overflow-hidden rounded-xl border border-border bg-border">
          <Skeleton className="h-11 w-full rounded-none" />
          <Skeleton className="h-11 w-full rounded-none" />
          <Skeleton className="h-11 w-full rounded-none" />
        </div>
      )}

      {data && data.items.length === 0 && (
        <div className="rounded-xl bg-muted px-6 py-14 text-center">
          <p className="text-3xl leading-none" aria-hidden>
            🍑
          </p>
          <p className="mt-4 font-heading text-base font-semibold">
            No items yet
          </p>
          <p className="mx-auto mt-1 max-w-sm text-sm text-muted-foreground">
            Create one to prove the round trip through the API and Postgres.
          </p>
          <Button
            size="lg"
            className="mt-5"
            onClick={() => {
              setEditing(null);
              setFormOpen(true);
            }}
          >
            <Plus data-icon="inline-start" className="size-4" />
            New item
          </Button>
        </div>
      )}

      {data && data.items.length > 0 && (
        <div className="overflow-x-auto rounded-xl border border-border">
          <Table>
            <TableHeader className="bg-muted/60">
              <TableRow className="hover:bg-transparent">
                <TableHead>Name</TableHead>
                <TableHead>Description</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Created</TableHead>
                <TableHead className="w-12" />
              </TableRow>
            </TableHeader>
            <TableBody>
              {data.items.map((item) => (
                <TableRow key={item.id}>
                  <TableCell className="font-medium">{item.name}</TableCell>
                  <TableCell className="max-w-sm truncate text-muted-foreground">
                    {item.description ?? "-"}
                  </TableCell>
                  <TableCell>
                    {/* Notion database tags: pastel fill, no border, tight radius. */}
                    <Badge variant={item.is_done ? "success" : "warning"}>
                      {item.is_done ? "Done" : "Open"}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-muted-foreground">
                    {new Date(item.created_at).toLocaleString()}
                  </TableCell>
                  <TableCell>
                    <DropdownMenu>
                      <DropdownMenuTrigger asChild>
                        <Button
                          variant="ghost"
                          size="icon"
                          aria-label={`Actions for ${item.name}`}
                        >
                          <MoreHorizontal className="size-4" />
                        </Button>
                      </DropdownMenuTrigger>
                      <DropdownMenuContent align="end">
                        <DropdownMenuItem
                          onSelect={() => {
                            setEditing(item);
                            setFormOpen(true);
                          }}
                        >
                          Edit
                        </DropdownMenuItem>
                        <DropdownMenuItem
                          variant="destructive"
                          onSelect={() => setPendingDelete(item)}
                        >
                          Delete
                        </DropdownMenuItem>
                      </DropdownMenuContent>
                    </DropdownMenu>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}

      <ItemFormDialog
        open={formOpen}
        onOpenChange={setFormOpen}
        item={editing}
      />

      <AlertDialog
        open={pendingDelete !== null}
        onOpenChange={(open) => !open && setPendingDelete(null)}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete this item?</AlertDialogTitle>
            <AlertDialogDescription>
              &quot;{pendingDelete?.name}&quot; will be removed permanently.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => pendingDelete && remove.mutate(pendingDelete)}
              disabled={remove.isPending}
            >
              Delete
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
