import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

import { ItemTable } from "@/components/item-table";
import { api } from "@/lib/api";
import { makeItem, renderWithQuery } from "./utils";

describe("ItemTable", () => {
  it("renders the empty state when there are no items", async () => {
    vi.spyOn(api, "listItems").mockResolvedValue({ items: [], total: 0 });
    renderWithQuery(<ItemTable />);
    await waitFor(() =>
      expect(screen.getByText("No items yet")).toBeInTheDocument(),
    );
  });

  it("renders a row per item", async () => {
    vi.spyOn(api, "listItems").mockResolvedValue({
      items: [makeItem(), makeItem({ id: "2", name: "Second", is_done: true })],
      total: 2,
    });
    renderWithQuery(<ItemTable />);

    await waitFor(() =>
      expect(screen.getByText("Example")).toBeInTheDocument(),
    );
    expect(screen.getByText("Second")).toBeInTheDocument();
    expect(screen.getByText("Done")).toBeInTheDocument();
    expect(screen.getByText("Open")).toBeInTheDocument();
    expect(screen.getByText("2 records")).toBeInTheDocument();
  });

  it("surfaces a retry affordance when loading fails", async () => {
    vi.spyOn(api, "listItems").mockImplementation(async () => {
      throw new Error("Could not reach the API");
    });
    renderWithQuery(<ItemTable />);

    await waitFor(() =>
      expect(screen.getByText("Could not load items")).toBeInTheDocument(),
    );
    expect(screen.getByRole("button", { name: "Retry" })).toBeInTheDocument();
  });

  it("opens the create dialog from the empty state", async () => {
    vi.spyOn(api, "listItems").mockResolvedValue({ items: [], total: 0 });
    renderWithQuery(<ItemTable />);

    await waitFor(() =>
      expect(screen.getByText("No items yet")).toBeInTheDocument(),
    );
    await userEvent.click(
      screen.getAllByRole("button", { name: /new item/i })[0],
    );

    expect(await screen.findByRole("dialog")).toBeInTheDocument();
    expect(
      screen.getByRole("heading", { name: "New item" }),
    ).toBeInTheDocument();
  });
});
