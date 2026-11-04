# Costos DEMO: las cuentas a mano

Compuerta de la etapa 2.3: **los costos DEMO coinciden con el cálculo a mano.** La validan Joaco y el Controller.

Los precios son **ficticios** (`supabase/seed.sql`). Son de grupo, con factura y 21 % de IVA incluido. Una prueba (`supabase/tests/230_recipe_costs.test.sql`) controla que el sistema dé estos números.

**Cómo se lee:** costo por gramo = precio del envase / contenido del envase. Costo de la línea = cantidad × costo por gramo. Sin IVA = con IVA / 1,21.

## Vacío a la parrilla (`DEMO-PAR-02`, 1 porción)

| Línea     | Cantidad | Envase            | Por gramo | Costo con IVA  |
| --------- | -------- | ----------------- | --------- | -------------- |
| Vacío     | 400 g    | $ 17.500 por 1 kg | $ 17,50   | $ 7.000,00     |
| Sal fina  | 6 g      | $ 37.500 por 5 kg | $ 7,50    | $ 45,00        |
| **Total** |          |                   |           | **$ 7.045,00** |

Sin IVA: 7.045 / 1,21 = **$ 5.822,31**.

## Salsa bolognesa (`DEMO-SAL-02`, rinde 3 kg)

| Línea                   | Cantidad | Envase             | Por g o ml | Costo con IVA   |
| ----------------------- | -------- | ------------------ | ---------- | --------------- |
| Carne picada especial   | 1.500 g  | $ 11.500 por 1 kg  | $ 11,50    | $ 17.250,00     |
| Tomate triturado        | 1.500 g  | $ 35.500 por 1 kg  | $ 35,50    | $ 53.250,00     |
| Cebolla                 | 400 g    | $ 2.500 por 10 kg  | $ 0,25     | $ 100,00        |
| Zanahoria               | 200 g    | $ 4.500 por 10 kg  | $ 0,45     | $ 90,00         |
| Vino tinto para cocinar | 200 ml   | $ 39.500 por 5 l   | $ 7,90     | $ 1.580,00      |
| Aceite de girasol       | 50 ml    | $ 34.500 por 5 l   | $ 6,90     | $ 345,00        |
| Sal fina                | 20 g     | $ 37.500 por 5 kg  | $ 7,50     | $ 150,00        |
| Laurel                  | 2 g      | $ 46.500 por 100 g | $ 465,00   | $ 930,00        |
| **Total**               |          |                    |            | **$ 73.695,00** |

Sin IVA: **$ 60.904,96**. Por gramo terminado, con IVA: 73.695 / 3.000 = $ 24,565.

## Ravioles de ricota (`DEMO-PAS-03`, 1 porción, con la bolognesa adentro)

| Línea           | Cantidad | De dónde sale      | Costo con IVA  |
| --------------- | -------- | ------------------ | -------------- |
| Harina 000      | 100 g    | $ 27.500 por 25 kg | $ 110,00       |
| Huevo           | 1        | $ 26.500 por 30    | $ 883,33       |
| Ricota          | 120 g    | $ 21.500 por 5 kg  | $ 516,00       |
| Queso rallado   | 20 g     | $ 9.000 por 5 kg   | $ 36,00        |
| Nuez moscada    | 0,5 g    | $ 44.500 por 100 g | $ 222,50       |
| Salsa bolognesa | 150 g    | $ 24,565 por gramo | $ 3.684,75     |
| **Total**       |          |                    | **$ 5.452,58** |

Sin IVA: **$ 4.506,27**. Sale **desactualizado**: el precio del queso rallado tiene 60 días.

## Ñoquis de papa (`DEMO-PAS-04`, rinde 1,2 kg, 4 porciones)

| Línea      | Cantidad | Envase             | Costo con IVA  |
| ---------- | -------- | ------------------ | -------------- |
| Papa       | 1.000 g  | $ 5.500 por 10 kg  | $ 550,00       |
| Harina 000 | 250 g    | $ 27.500 por 25 kg | $ 275,00       |
| Huevo      | 1        | $ 26.500 por 30    | $ 883,33       |
| Sal fina   | 8 g      | $ 37.500 por 5 kg  | $ 60,00        |
| **Total**  |          |                    | **$ 1.768,33** |

Sin IVA: $ 1.461,43. Por porción, sin IVA: 1.461,43 / 4 = **$ 365,36**.

## Lasaña bolognesa (`DEMO-PAS-05`): incompleta

La Salsa blanca lleva harina 0000, que no tiene precio. La Lasaña queda **incompleta**, y su costo vacío: nunca $ 0.
