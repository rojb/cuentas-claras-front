# Prompts — Splitter (TAP 2026)

Registro de los pedidos que construyeron la app, en orden. Están transcritos
del historial de la sesión, tal como se escribieron, incluidos los typos y las
correcciones sobre la marcha.

La app es un conciliador de gastos entre amigos: **Flutter** en el cliente,
**TypeScript + Express** en el backend, **PostgreSQL** como base de datos. Los
gastos se registran en bolivianos, dólares o USDT, y todo se salda en **USDT**.

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

## 7. Salir de un grupo, e invitaciones

Esta tanda salió de una sesión aparte, el 27 de agosto, entre el arranque de
Flutter y el trabajo de web. Son los pedidos que produjeron las migraciones
002 y 003.

**23.** — Pegado desde la terminal: el backend levantaba pero no encontraba la
base. Era el contenedor de Postgres apagado, no un bug.
> unhandled error AggregateError [ECONNREFUSED] ... Error: connect ECONNREFUSED 127.0.0.1:55432

**24.**
> Como puedo salir de un grupo de pago como usuario?

**25.** — De acá salió la regla: una membresía no se borra, se marca con
`left_at`. El ledger apunta a ella, así que borrarla dejaría deudas sin dueño.
> dale, implementalo con la migración y el caso de uso

**26.** — Una carrera real: entre leer el saldo de alguien y darlo de baja,
podía entrar un gasto nuevo a su nombre. Se arregló bloqueando las membresías
al leerlas.
> dale, arreglá la ventana en prepareExpense

**27.**
> Como hago para salirme de un grupo en el frontend

**28.**
> cablea así

**29.** — La app sabía que había una sesión, pero no de quién era; sin eso no
se puede dibujar "vos" en una lista de saldos.
> dale, agregale la identidad a Session

**30.** — Cambió el modelo: agregar a alguien dejó de ser un alta directa y
pasó a ser una pregunta que la otra persona contesta.
> para agregar a alguien a un grupo se necesita enviar una invitacion dentro de la app para que pueda aceptar o rechazar dicha invitación

**31.** — Acotó el alcance: se invita a usuarios que ya tienen cuenta. Invitar
por email a alguien sin cuenta es otra funcionalidad.
> para alguien previamente registrado

---

## 8. Web

**32.**
> habilitemos el proyecto para web

**33.** — Resultó ser el backend caído, no un problema de la app.
> Me sale que no pudo acceder al servidor

---

## 9. Idioma y moneda

**34.** — Escrito primero como "la moneda de bs" y corregido enseguida.
> pon la app en español y agregale la moneda de bolivianos

---

## 10. Checklist de la materia

**35.** — El pedido que destapó dos huecos reales: no existía el endpoint de
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

## 11. Cálculo en vivo

**36.** — Cambió una decisión de diseño anterior: hasta acá el editor solo
verificaba que los números cerraran, nunca calculaba cuánto le tocaba a cada
uno.
> Cuando calculamos como se dividen los gastos, tienen que calcularse automaticamente pero también tiene que permitir editar y recalcular automátcamente cuando se edita

---

## 12. Documentación

**37.**
> haz el .md con todos los prompts que hicimos para construir la app

---

## 13. Multimoneda y conciliación en USDT

**38.** — Trajo la rama con las invitaciones, que se había trabajado en otra
máquina.
> git pull en ambos respositorios

**39.**
> Muy bien, ahora tenemos un nuevo requerimiento, nosotros ahora mismo creamos el grupo con una moneda en específico, quiero que eso ya no sea así, en cambio de eso, los gastos de grupo pueden ser multimonedas y solo se podrán hacer en estas monedas USDT, Bolivianos (BOB), USD pero todo se conciliará en dólares cripto (USDT) Un ejemplo: Ruben debe 10 usdt a Nathalia. Se debe considerar un tipo de cambio para la conversión a usdt al momento de conciliar. Auenque gasto haya sido en bolivianos, debe de convertirse a usdt.

**40.** — La pregunta que cerró la única decisión ambigua del pedido: si el
tipo de cambio se congela en el gasto o se aplica al conciliar.
> A cuenato equivale el 46.40?

**41.** — La decisión. Elegida sobre "la deuda en bolivianos" una vez visto
que convertir al leer rompe la suma cero: `round(a×r) + round(b×r)` no es
`round((a+b)×r)`.
> La deuda en USDT

---

## 14. Documentación, otra vez

**42.** — El mismo pedido que el 37, ya con el cambio de monedas hecho.
Contestarlo destapó que faltaba una sesión entera en este archivo: los nueve
pedidos del 27 de agosto que produjeron el salir de un grupo y las
invitaciones (sección 7). Estaban en el historial y no acá.
> Guarda los prompt que hemos hecho en mi historial de prompts

---

## 15. De dónde sale el tipo de cambio

**43.** — La pregunta correcta, y la respuesta corta es **de ningún lado**: no
hay price feed ni API. Lo escribe la persona que carga el gasto, y lo único
que la app sugiere es el último cambio que ese grupo usó de verdad, leído de
sus propios gastos. Sobre el 0,99: es cierto que un USDT no es exactamente un
dólar, y el diseño ya lo contempla — **USD lleva su propio tipo de cambio**,
como cualquier otra moneda. Lo único forzado a la par es USDT contra sí mismo,
que es una tautología y no una afirmación sobre el mercado.
> El valor de el usdt de donde lo estas sacando? no que un usdt es igual a 0.99 $?

---

## 16. Quién puede registrar un pago, e historial

**44.** — Dos pedidos en uno: un permiso y una pantalla.
> Quiero que solamente la persona que registró el pago, el anfitrion o el que tiene que pagar puedan registrar el pago, además, que haya historial de pagos o deudas por cada grupo por cada gasto.

**45.** — Respuesta a una pregunta: el que **recibe** la plata no estaba en la
lista de los tres, y es de los que más naturalmente registra un pago
("ya me pagó, lo anoto").
> sumalo al que recibe también

**46.** — Escrito a mitad de trabajo. Confirmó la regla desde el otro lado:
alguien sin nada que ver con el pago no lo puede tocar.
> Si yo no debo a nadie, no tendria que poder registrar el pago de otros

---

## 17. Documentación, la tercera

**47.**
> actualiza el PROMPTS.md con estos últimos pedidos

---

## Apéndice — decisiones que salieron de estos pedidos

Cosas que no estaban en ningún prompt pero que se decidieron construyendo, y
que conviene poder defender:

| Decisión | Por qué |
|---|---|
| Solo se guardan dos hechos: `Expense` y `Payment` | Los saldos se derivan siempre, nunca se almacenan. Por eso "pago parcial" (prompt 1) no necesitó código propio: se registra lo que se entregó y el saldo dice lo que falta. |
| Enteros en todos lados | Centavos para plata, puntos base para porcentajes (10000 = 100%), enteros relativos para partes. Cero coma flotante cerca del dinero. |
| Método del resto mayor | Los centavos que sobran van a quien más perdió al redondear; empates al primero de la lista. Es la respuesta a la pista del prompt 35: **Bs 100 entre 3 = 33,34 + 33,33 + 33,33**. |
| Editar un gasto lo anula y escribe uno nuevo | Es un ledger, no un CRUD. Reusa `voidExpense` + `writeExpense`, que ya existían y ya eran correctos, así que no hay un segundo camino por donde la suma cero pueda romperse. El precio: **cambia el id del gasto**. |
| Validar antes de abrir la transacción | Un split inválido al editar devuelve 422 y el gasto original queda intacto. |
| `requireMembership()` devuelve 404, no 403 | Un 403 confirmaría que el grupo existe. |
| El server manda un `code`, el cliente pone las palabras | Por eso traducir la app al español (prompt 34) no tocó una línea del backend. |
| El cálculo en vivo es un preview | `allocate` en Dart es un porte línea por línea del dominio del server, verificado contra él en 240 casos. Si alguna vez difieren, **manda el server**. |
| Una membresía no se borra, se marca con `left_at` | El ledger apunta a ella. Borrarla dejaría deudas sin dueño, así que salir de un grupo es un hecho con fecha, igual que todo lo demás acá. |
| Las invitaciones viven en su propia tabla | Una fila en `group_members` no significa "esta persona está asociada al grupo", significa **a esta persona se le puede cobrar plata**. Una invitación pendiente ahí dejaría que la base acepte un gasto a nombre de alguien que todavía no dijo que sí. |
| El tipo de cambio se congela en el gasto | Decidido en el prompt 41. Un gasto es un hecho, y el cambio de esa noche es parte del hecho. Convertir al leer haría que los saldos se muevan solos de un día para el otro, que un pago completo deje de serlo a la mañana siguiente, y que un saldo de la semana pasada no se pueda reproducir. |
| Convertir el TOTAL una vez, y recién después dividir | Las partes en la moneda original se usan como **pesos** para repartir el total ya convertido. Convertir cada parte por separado redondea cada una por separado y dejan de sumar el total: `round(a×r) + round(b×r)` no es `round((a+b)×r)`. Es la misma pista del prompt 35, un nivel más arriba. |
| Un gasto en USDT solo se acepta a la par | Se valida en el dominio, en un CHECK de la base, y el campo directamente no aparece en la pantalla. "1 USDT = 1,02 USDT" no es un tipo de cambio, es un error de tipeo. |
| Menos de un centavo de USDT se rechaza | Bs 0,01 a 6,96 convierte a 0. Redondear para arriba inventa plata y para abajo cobra por nada, así que devuelve 422 `amount_too_small`. |
| El tipo de cambio lo escribe la persona | No hay price feed. Lo único que se ofrece es el último cambio que ese grupo usó de verdad, leído de sus propios gastos; sin historial, el campo va vacío. En Bolivia el USDT no cotiza cerca del oficial, así que el único número que sirve es el que esas personas realmente pagaron. |
| Un pago lo registran las dos puntas, o el anfitrión | Prompts 44 a 46. Registrar un pago mueve el saldo de otro, así que no es una nota que cualquiera del grupo deje sobre dos terceros. "Anfitrión" no es un rol nuevo: es `expense_groups.created_by`, que ya existía. |
| Eliminar suma a quien lo registró | El motivo más común para borrar un pago es que quien lo tipeó se equivocó. Si tiene que ir a buscar al anfitrión por un typo, la corrección no se hace. |
| 403 acá, y no 404 como en `requireMembership` | El 404 existe para no confirmar que un grupo existe. Acá la persona ya es miembro y ya ve el grupo: no queda nada que esconder, lo único que se niega es la escritura. |
| La UI esconde botones que el server igual rechaza | El campo, el botón de Liquidar y el de borrar en Historial se dibujan según la misma regla — pero es una pista para no llenar un formulario que iba a rebotar, no el candado. El candado está en el server, y se prueba por separado. |

## Apéndice — qué se verificó y cómo

Sin tests, la verificación fue toda contra el sistema corriendo:

- **Backend**: `npm run typecheck` y llamadas reales con `curl` contra Postgres
  en Docker, para las seis estrategias, los saldos, la liquidación, los pagos
  parciales, el alta/edición/borrado de gastos y los códigos de error.
- **Reparto**: 240 casos generados al azar, calculados en Dart y en el server,
  comparados uno a uno. **240 idénticos**, y en todos la suma de las partes da
  exacto el total. Repetido después del cambio de monedas, ahora sobre tres
  monedas y tipos de cambio incómodos (13,333333 / 999,999999): **259 casos,
  0 diferencias**.
- **Multimoneda**: la migración 004 se aplicó sobre **281 gastos reales** ya
  cargados; los 41 saldos quedaron idénticos y todos los grupos siguieron
  sumando cero. Después, 218 gastos al azar en las tres monedas más 18 pagos:
  la suma cero se mantuvo y la liquidación dejó a todos en cero.
- **Permisos**: 24 comprobaciones contra el server con cuatro usuarios —
  anfitrión, dos que se deben plata, y un cuarto sin nada que ver. Cada quién
  puede y cada quién no, en registrar y en eliminar, incluido el caso del
  prompt 46: el cuarto integrante recibe **403** en las dos operaciones.
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
