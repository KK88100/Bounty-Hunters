"use client";

import { BellIcon } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { toastManager, type ThreadToastData } from "~/components/ui/toast";
import {
  Sheet,
  SheetHeader,
  SheetPanel,
  SheetPopup,
  SheetTitle,
  SheetTrigger,
} from "~/components/ui/sheet";
import { ScrollArea } from "~/components/ui/scroll-area";
import { Button } from "~/components/ui/button";
import { cn } from "~/lib/utils";
import {
  useNotificationStore,
  type NotificationType,
} from "~/stores/notificationStore";
import { SidebarMenuButton } from "~/components/ui/sidebar";

// ─── Icon mapping ───────────────────────────────────────────────────────────────

const TYPE_ICONS: Record<string, string> = {
  success: "✓",
  error: "✕",
  warning: "⚠",
  info: "ℹ",
  loading: "◌",
};

const TYPE_COLORS: Record<string, string> = {
  success: "text-success bg-success/10 border-success/20",
  error: "text-destructive bg-destructive/10 border-destructive/20",
  warning: "text-warning bg-warning/10 border-warning/20",
  info: "text-info bg-info/10 border-info/20",
  loading: "text-muted-foreground bg-muted/30 border-muted/40",
};

// ─── Notify helper ──────────────────────────────────────────────────────────────

export type NotifyOptions = {
  type: NotificationType;
  title: string;
  description?: string;
  /** Duration in ms before auto-dismiss (default: 5000). Set to 0 for no auto-dismiss. */
  duration?: number;
  actionProps?: React.ComponentPropsWithoutRef<"button">;
  data?: Omit<ThreadToastData, "actionLayout">;
};

/**
 * Show a toast notification AND record it in the notification history.
 *
 * Replaces bare `toastManager.add()` / `stackedThreadToast()` calls where
 * history tracking is desired.
 */
export function notify(options: NotifyOptions): string {
  const {
    type,
    title,
    description,
    duration = 5000,
    actionProps,
    data,
  } = options;

  const toastData: ThreadToastData = {
    ...(data ?? {}),
    actionLayout: "stacked-end",
    dismissAfterVisibleMs: duration > 0 ? duration : undefined,
  };

  const toastId = toastManager.add({
    type,
    title,
    description,
    timeout: duration > 0 ? duration : undefined,
    actionProps,
    data: toastData,
  });

  // Record in history
  useNotificationStore.getState().addToHistory({
    type,
    title,
    description,
  });

  return toastId;
}

/**
 * Shortcut: show an info toast.
 */
export function notifyInfo(title: string, description?: string, duration?: number): string {
  return notify({ type: "info", title, description, duration });
}

/**
 * Shortcut: show a success toast.
 */
export function notifySuccess(title: string, description?: string, duration?: number): string {
  return notify({ type: "success", title, description, duration });
}

/**
 * Shortcut: show a warning toast.
 */
export function notifyWarning(title: string, description?: string, duration?: number): string {
  return notify({ type: "warning", title, description, duration });
}

/**
 * Shortcut: show an error toast.
 */
export function notifyError(title: string, description?: string, duration?: number): string {
  return notify({ type: "error", title, description, duration });
}

// ─── History panel ──────────────────────────────────────────────────────────────

/**
 * Notification history panel, shown in a sheet from the sidebar.
 */
export function NotificationHistory() {
  const [open, setOpen] = useState(false);
  const history = useNotificationStore((s) => s.history);
  const unreadCount = useNotificationStore((s) => s.unreadCount);
  const markAsRead = useNotificationStore((s) => s.markAsRead);
  const markAllAsRead = useNotificationStore((s) => s.markAllAsRead);
  const clearHistory = useNotificationStore((s) => s.clearHistory);
  const removeFromHistory = useNotificationStore((s) => s.removeFromHistory);

  const handleOpenChange = useCallback(
    (nextOpen: boolean) => {
      setOpen(nextOpen);
      if (nextOpen) {
        // Mark all as read when opening
        markAllAsRead();
      }
    },
    [markAllAsRead],
  );

  return (
    <>
      {/* Sidebar menu button */}
      <SidebarMenuButton
        size="sm"
        className="relative gap-2 px-2 py-1.5 text-muted-foreground/70 hover:bg-accent hover:text-foreground"
        onClick={() => setOpen(true)}
      >
        <BellIcon className="size-3.5" />
        <span className="text-xs">Notifications</span>
        {unreadCount > 0 && (
          <span className="absolute right-1.5 top-1/2 -translate-y-1/2 inline-flex min-w-[18px] items-center justify-center rounded-full bg-primary px-1 py-0.5 text-[10px] font-semibold leading-none text-primary-foreground">
            {unreadCount > 99 ? "99+" : unreadCount}
          </span>
        )}
      </SidebarMenuButton>

      {/* Sheet panel */}
      <Sheet open={open} onOpenChange={handleOpenChange}>
        <SheetPopup side="right" className="w-96 max-w-[calc(100vw-3rem)]">
          <SheetHeader>
            <SheetTitle>Notification History</SheetTitle>
          </SheetHeader>
          <SheetPanel>
            {history.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-12 text-center text-muted-foreground">
                <BellIcon className="mb-3 size-8 opacity-40" />
                <p className="text-sm">No notifications yet</p>
                <p className="mt-1 text-xs text-muted-foreground/60">
                  Notifications will appear here as they arrive.
                </p>
              </div>
            ) : (
              <>
                <div className="mb-3 flex items-center justify-between">
                  <span className="text-xs text-muted-foreground">
                    {history.length} notification{history.length !== 1 ? "s" : ""}
                  </span>
                  <div className="flex gap-1">
                    <Button
                      size="xs"
                      variant="ghost"
                      className="text-xs"
                      onClick={markAllAsRead}
                    >
                      Mark all read
                    </Button>
                    <Button
                      size="xs"
                      variant="ghost"
                      className="text-xs text-destructive/70 hover:text-destructive"
                      onClick={clearHistory}
                    >
                      Clear all
                    </Button>
                  </div>
                </div>
                <ScrollArea className="h-[calc(100vh-12rem)]">
                  <div className="flex flex-col gap-1">
                    {history.map((entry) => (
                      <div
                        key={entry.id}
                        className={cn(
                          "group relative flex items-start gap-2.5 rounded-lg border p-3 text-sm transition-colors",
                          TYPE_COLORS[entry.type] ?? "text-muted-foreground bg-muted/30 border-muted/40",
                          !entry.read && "ring-1 ring-primary/10",
                        )}
                      >
                        {/* Icon indicator */}
                        <span className="mt-0.5 flex size-5 shrink-0 items-center justify-center text-xs font-bold">
                          {TYPE_ICONS[entry.type] ?? "•"}
                        </span>

                        {/* Content */}
                        <div className="min-w-0 flex-1">
                          <div className="flex items-start justify-between gap-2">
                            <span
                              className={cn(
                                "text-sm font-medium",
                                !entry.read && "text-foreground",
                              )}
                            >
                              {String(entry.title)}
                            </span>
                            <button
                              className="mt-0.5 shrink-0 text-muted-foreground/40 opacity-0 transition-opacity hover:text-muted-foreground group-hover:opacity-100"
                              onClick={() => removeFromHistory(entry.id)}
                              aria-label="Remove"
                            >
                              ✕
                            </button>
                          </div>
                          {entry.description && (
                            <p className="mt-0.5 text-xs text-muted-foreground/80">
                              {String(entry.description)}
                            </p>
                          )}
                          <p className="mt-1 text-[10px] text-muted-foreground/40">
                            {formatTimestamp(entry.timestamp)}
                          </p>
                        </div>
                      </div>
                    ))}
                  </div>
                </ScrollArea>
              </>
            )}
          </SheetPanel>
        </SheetPopup>
      </Sheet>
    </>
  );
}

// ─── Helpers ────────────────────────────────────────────────────────────────────

function formatTimestamp(ts: number): string {
  const diff = Date.now() - ts;
  if (diff < 60_000) return "Just now";
  if (diff < 3_600_000) return `${Math.floor(diff / 60_000)}m ago`;
  if (diff < 86_400_000) return `${Math.floor(diff / 3_600_000)}h ago`;
  if (diff < 604_800_000) return `${Math.floor(diff / 86_400_000)}d ago`;
  return new Date(ts).toLocaleDateString();
}
