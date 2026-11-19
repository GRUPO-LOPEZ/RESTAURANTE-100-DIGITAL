import {
  BookOpen,
  Calculator,
  Clock,
  FileText,
  House,
  Inbox,
  KeyRound,
  LayoutDashboard,
  Package,
  PackageCheck,
  ReceiptText,
  Receipt,
  Wallet,
  ChartColumn,
  ShoppingCart,
  Tags,
  Truck,
  ShieldCheck,
  Users,
  Warehouse,
  type LucideIcon,
} from "lucide-react";

import type { NavIcon } from "@/lib/nav";

// Íconos de trazo de la navegación (ADR-0036): el mismo set (Lucide) en todo el sistema.
const ICONS: Record<NavIcon, LucideIcon> = {
  home: House,
  panel: LayoutDashboard,
  recipes: BookOpen,
  ingredients: Package,
  rubros: Tags,
  suppliers: Truck,
  priceLists: ReceiptText,
  orders: ShoppingCart,
  receipts: PackageCheck,
  invoices: Receipt,
  payments: Wallet,
  purchasingBoard: ChartColumn,
  inventory: Warehouse,
  costs: Calculator,
  reports: FileText,
  quality: ShieldCheck,
  approvals: Inbox,
  users: Users,
  roles: KeyRound,
  history: Clock,
};

export function NavIconGlyph({ icon, className }: { icon: NavIcon; className?: string }) {
  const Icon = ICONS[icon];
  return <Icon aria-hidden="true" className={className ?? "size-5 shrink-0"} />;
}
