import { create } from "zustand";
import { persist } from "zustand/middleware";
import type { ReactNode } from "react";

export type NotificationType = "success" | "error" | "warning" | "info" | "loading";

export interface NotificationEntry {
  id: string;
  type: NotificationType;
  title: ReactNode;
  description?: ReactNode;
  timestamp: number;
  dismissed: boolean;
  read: boolean;
}

interface NotificationState {
  /** Ordered list of notifications (newest first). */
  history: NotificationEntry[];
  /** Maximum number of entries to retain. */
  maxEntries: number;
  /** Unread count (derived from history). */
  unreadCount: number;
}

interface NotificationActions {
  /** Add a notification to history. */
  addToHistory: (
    entry: Omit<NotificationEntry, "id" | "timestamp" | "dismissed" | "read">,
  ) => string;
  /** Mark a notification as read. */
  markAsRead: (id: string) => void;
  /** Mark all notifications as read. */
  markAllAsRead: () => void;
  /** Remove a single entry from history. */
  removeFromHistory: (id: string) => void;
  /** Clear all history. */
  clearHistory: () => void;
  /** Recalculate unread count. */
  recalculateUnreadCount: () => void;
}

export type NotificationStore = NotificationState & NotificationActions;

let nextId = 1;
function generateId(): string {
  return `notification-${Date.now()}-${nextId++}`;
}

const MAX_ENTRIES = 100;

export const useNotificationStore = create<NotificationStore>()(
  persist(
    (set, get) => ({
      // State
      history: [],
      maxEntries: MAX_ENTRIES,
      unreadCount: 0,

      // Actions
      addToHistory: (entry) => {
        const id = generateId();
        const newEntry: NotificationEntry = {
          ...entry,
          id,
          timestamp: Date.now(),
          dismissed: false,
          read: false,
        };
        set((state) => {
          const next = [newEntry, ...state.history].slice(0, state.maxEntries);
          const unreadCount = next.filter((n) => !n.read).length;
          return { history: next, unreadCount };
        });
        return id;
      },

      markAsRead: (id) => {
        set((state) => {
          const next = state.history.map((n) => (n.id === id ? { ...n, read: true } : n));
          const unreadCount = next.filter((n) => !n.read).length;
          return { history: next, unreadCount };
        });
      },

      markAllAsRead: () => {
        set((state) => {
          const next = state.history.map((n) => ({ ...n, read: true }));
          return { history: next, unreadCount: 0 };
        });
      },

      removeFromHistory: (id) => {
        set((state) => {
          const next = state.history.filter((n) => n.id !== id);
          const unreadCount = next.filter((n) => !n.read).length;
          return { history: next, unreadCount };
        });
      },

      clearHistory: () => {
        set({ history: [], unreadCount: 0 });
      },

      recalculateUnreadCount: () => {
        set((state) => ({
          unreadCount: state.history.filter((n) => !n.read).length,
        }));
      },
    }),
    {
      name: "t3code:notification-history:v1",
      partialize: (state) => ({
        history: state.history.map((n) => ({
          ...n,
          title: typeof n.title === "string" ? n.title : "[Notification]",
          description:
            typeof n.description === "string"
              ? n.description
              : n.description !== undefined
                ? "[Details]"
                : undefined,
        })),
      }),
    },
  ),
);
