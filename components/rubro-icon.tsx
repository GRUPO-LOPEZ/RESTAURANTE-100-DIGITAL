import {
  Beef,
  CakeSlice,
  Carrot,
  Droplet,
  Fish,
  GlassWater,
  Leaf,
  Milk,
  Package,
  ShoppingBag,
  Soup,
  SprayCan,
  Utensils,
  Wheat,
  type LucideIcon,
} from "lucide-react";

import type { RubroIconKey } from "@/lib/rubros";

// Los íconos de los rubros (ADR-0066): un set fijo. Van siempre con el nombre al lado.
const ICONS: Record<RubroIconKey, LucideIcon> = {
  vegetable: Carrot,
  meat: Beef,
  fish: Fish,
  dairy: Milk,
  flour: Wheat,
  oil: Droplet,
  herb: Leaf,
  pantry: Package,
  drink: GlassWater,
  cleaning: SprayCan,
  packaging: ShoppingBag,
  preparation: Soup,
  dish: Utensils,
  dessert: CakeSlice,
};

export function RubroIcon({ icon, className }: { icon: RubroIconKey; className?: string }) {
  const Icon = ICONS[icon];
  return <Icon aria-hidden="true" className={className ?? "size-4 shrink-0"} />;
}
