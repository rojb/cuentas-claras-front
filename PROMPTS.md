# Prompts — Splitter (TAP 2026)

Registro de los pedidos que construyeron la app, en orden. Están transcritos
del historial de la sesión, tal como se escribieron, incluidos los typos y las
correcciones sobre la marcha.

La app es un conciliador de gastos entre amigos: **Flutter** en el cliente,
**TypeScript + Express** en el backend, **PostgreSQL** como base de datos.

---

## 1. Definición del problema

**1.** 
> Quiero hacer una app móvil para para conciliar pagos entre amigos, es esta app quiero que las personas se puedan registrar, puedan tener grupos de gastos, poder agregar personas o amigos al grupo de gasto y registrar gastos dentro de ese grupo. Deben de existir varias formas de dividir gastos, como ser: División equitativa, por cantidades específicas, por porcentajes, por partes, o división personalizada. Además debe de poder calcular si varias personas hicieron gastos dentro de un grupo de gastos. La app obviamente debe de poder hacer la conciliación/liquidación de las deudas y registrar cuando se pagó una deuda, ya sea completa o en pagos parciales.

**2.**
> El stack es libre pero sabemos más flutter

**3.**
> tengo que hacer un backend

**4.**
> Vamos, usemos typescript

**5.**
> No se que es eso del domino utiliza algo más fácil

---

## 2. Restricciones de trabajo

Estos dos pedidos fijaron una regla que se respetó durante todo el proyecto:
**no hay archivos de test ni de spec en ningún lado.** La verificación se hizo
con `npm run typecheck`, `flutter analyze` y corridas reales contra el backend
levantado con Docker.

**6.**
> no hagas pruebas ni spec, no las necesito para este proyecto

**7.**
> no hagas pruebas .test.test ni .spec, no las necesito para este proyecto

---

## 3. El dominio: las seis formas de dividir

Se construyó una estrategia por vez, cada una verificada antes de pasar a la
siguiente.

**8.**
> Arranquemos con la división equitativa

**9.**
> sigamos con montos específicos

**10.**
> Vamos con porcentajes ahora

**11.**
> Vamos con partes ahora

**12.** — Acá se aclaró qué significaba "división personalizada": son dos cosas
distintas, la mixta y la cuenta por ítems.
> En personalizada me referia a que la mixta y a este caso
> Hamburguesa → Juan
> Pizza → Juan + Ana
> Bebidas → todos
> Propina → todos

**13.**
> arranca con items

---

## 4. Saldos y liquidación

**14.**
> Vamos con saldos

**15.**
> vamos con la liquidación

---

## 5. Persistencia y API

**16.**
> Vamos ahora con la base de datos

**17.**
> arranca con la api ahora

**18.**
> seguimos con los grupos

**19.**
> dale con el gasto

**20.**
> Cerramos el backend

---

## 6. Cliente Flutter

**21.**
> arranca con flutter

**22.** — Respuesta a una pregunta sobre manejo de estado. Se eligió
**Flutter puro**: `ValueNotifier`, `ChangeNotifier` e `InheritedWidget`, sin
librerías de terceros.
> Solo Flutter

---

## 7. Web

**23.**
> habilitemos el proyecto para web

**24.** — Resultó ser el backend caído, no un problema de la app.
> Me sale que no pudo acceder al servidor

---

## 8. Idioma y moneda

**25.** — Escrito primero como "la moneda de bs" y corregido enseguida.
> pon la app en español y agregale la moneda de bolivianos

---

## 9. Checklist de la materia

**26.** — El pedido que destapó dos huecos reales: no existía el endpoint de
edición de gastos, y el de borrado existía pero la UI nunca lo llamaba.
> Funcionalidad mínima esperada (ambos grupos)
> - Agregar y listar participantes.
> - Registrar un gasto: descripción, monto, quién pagó, entre quiénes se divide (por defecto todos, pero debe poderse excluir gente de un gasto).
> - Editar y eliminar gastos.
> - Pantalla de saldos: balance de cada participante (positivo = le deben, negativo = debe).
> - Pantalla de liquidación: lista de transferencias "X → Y: monto" para quedar a mano.
> - Los datos sobreviven al refrescar la página.
>
> Pista matemática: la suma de todos los balances debe dar siempre exactamente 0. Si en algún momento no da 0, tienen un bug (probablemente de redondeo). Piensen qué hacen con los centavos cuando Bs. 100 se divide entre 3.

---

## 10. Cálculo en vivo

**27.** — Cambió una decisión de diseño anterior: hasta acá el editor solo
verificaba que los números cerraran, nunca calculaba cuánto le tocaba a cada
uno.
> Cuando calculamos como se dividen los gastos, tienen que calcularse automaticamente pero también tiene que permitir editar y recalcular automátcamente cuando se edita

---

## 11. Documentación

**28.**
> haz el .md con todos los prompts que hicimos para construir la app

---

## Apéndice — decisiones que salieron de estos pedidos

Cosas que no estaban en ningún prompt pero que se decidieron construyendo, y
que conviene poder defender:

| Decisión | Por qué |
|---|---|
| Solo se guardan dos hechos: `Expense` y `Payment` | Los saldos se derivan siempre, nunca se almacenan. Por eso "pago parcial" (prompt 1) no necesitó código propio: se registra lo que se entregó y el saldo dice lo que falta. |
| Enteros en todos lados | Centavos para plata, puntos base para porcentajes (10000 = 100%), enteros relativos para partes. Cero coma flotante cerca del dinero. |
| Método del resto mayor | Los centavos que sobran van a quien más perdió al redondear; empates al primero de la lista. Es la respuesta a la pista del prompt 26: **Bs 100 entre 3 = 33,34 + 33,33 + 33,33**. |
| Editar un gasto lo anula y escribe uno nuevo | Es un ledger, no un CRUD. Reusa `voidExpense` + `writeExpense`, que ya existían y ya eran correctos, así que no hay un segundo camino por donde la suma cero pueda romperse. El precio: **cambia el id del gasto**. |
| Validar antes de abrir la transacción | Un split inválido al editar devuelve 422 y el gasto original queda intacto. |
| `requireMembership()` devuelve 404, no 403 | Un 403 confirmaría que el grupo existe. |
| El server manda un `code`, el cliente pone las palabras | Por eso traducir la app al español (prompt 25) no tocó una línea del backend. |
| El cálculo en vivo es un preview | `allocate` en Dart es un porte línea por línea del dominio del server, verificado contra él en 240 casos. Si alguna vez difieren, **manda el server**. |

## Apéndice — qué se verificó y cómo

Sin tests, la verificación fue toda contra el sistema corriendo:

- **Backend**: `npm run typecheck` y llamadas reales con `curl` contra Postgres
  en Docker, para las seis estrategias, los saldos, la liquidación, los pagos
  parciales, el alta/edición/borrado de gastos y los códigos de error.
- **Reparto**: 240 casos generados al azar, calculados en Dart y en el server,
  comparados uno a uno. **240 idénticos**, y en todos la suma de las partes da
  exacto el total.
- **Ida y vuelta del split**: las seis estrategias se guardan y se releen
  idénticas, incluida la mixta —donde la *ausencia* de monto es el
  significado— y los ítems anidados con propina proporcional.
- **Navegador**: la app se levantó en Edge headless por CDP. Arranca sin
  errores de consola, `localStorage` sobrevive al refresh, y se sacaron
  capturas del cálculo en vivo (Bs 100 entre 3, el recálculo al cambiar el
  total, y un centavo entre tres).

**Lo que no se verificó**: nadie hizo el flujo completo apretando botones en
un navegador real. Manejar el input de texto de Flutter web por CDP no se
pudo — CanvasKit dibuja en canvas y el input vive en un shadow DOM.
