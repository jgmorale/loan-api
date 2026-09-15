# Use case container + state machine modules

## Contexto

Hoy los use cases (`RegisterPayment`, `ApplyPayment`) se instancian con `.new` en
cada punto de llamada (`V1::External::PaymentsController#create` y
`PaymentCreatedListener#call`), generando un objeto nuevo por invocación. El
estado de `Loan` vive como `state_machine` inline dentro de `app/models/loan.rb`
y `Payment` no tiene máquina de estado (solo `validates :status, inclusion:`).

En el proyecto hermano `payments-api` ya existe este mismo patrón resuelto:
un `UseCaseContainer` (`Dry::Container` + `Dry::AutoInject`) registrado en un
initializer con instancias memoizadas, y un concern `Transitionable` que
encapsula el `state_machine` de `Payment` fuera del modelo.

## Objetivo

1. Introducir `UseCaseContainer` en `loan-api` para memoizar instancias de los
   use cases (y adaptadores relacionados) sin usar variables globales sueltas.
2. Extraer la máquina de estado de `Payment` a un concern `Transitionable`
   (created → validated → applied), replicando el patrón de payments-api.
3. Mover la máquina de estado de `Loan`, hoy inline en el modelo, a su propio
   concern (`LoanTransitionable`), sin cambiar su comportamiento.

## Fuera de alcance

- No se agregan nuevos estados/transiciones no usados hoy (p. ej. `rejected`
  en `Payment`).
- No se usa `Dry::AutoInject` dentro de los use cases (`RegisterPayment`,
  `ApplyPayment`): no tienen dependencias externas inyectables hoy, solo se
  memoizan como instancia única en el container.
- No se modifica la lógica de negocio de `ApplyPayment`/`RegisterPayment`.

## Diseño

### 1. `UseCaseContainer`

Nuevo `config/initializers/01_use_case_container.rb`:

```ruby
require "dry-container"
require "dry-auto_inject"

UseCaseContainer = Dry::Container.new

UseCaseContainer.register(:kafka_event_publisher, memoize: true) { KafkaEventPublisher.new }
UseCaseContainer.register(:outbox_publisher, memoize: true) do
  OutboxPublisher.new(event_publisher: UseCaseContainer[:kafka_event_publisher])
end
UseCaseContainer.register(:register_payment, memoize: true) { RegisterPayment.new }
UseCaseContainer.register(:apply_payment, memoize: true) { ApplyPayment.new }
```

Puntos de llamada actualizados para resolver desde el container en lugar de
`.new`:

- `app/controllers/v1/external/payments_controller.rb`: método privado
  `register_payment` que devuelve `UseCaseContainer[:register_payment]`.
- `app/listeners/payment_created_listener.rb`: método privado `apply_payment`
  que devuelve `UseCaseContainer[:apply_payment]`.

### 2. `Transitionable` (Payment)

`app/models/concerns/transitionable.rb`:

```ruby
module Transitionable
  extend ActiveSupport::Concern

  included do
    state_machine :status, initial: :created, use_transactions: false do
      event :validate_payment do
        transition created: :validated
      end

      event :apply do
        transition validated: :applied
      end
    end
  end
end
```

`Payment` incluye el concern y deja de declarar `STATUSES` /
`validates :status, inclusion:` (el `state_machine` ya restringe los valores
válidos de `status`).

`PaymentCreatedListener#call`, dentro del `Payment.transaction do ... end` que
ya existe, reemplaza las actualizaciones manuales de `status` por los eventos
del state machine:

```ruby
payment.validate_payment! if payment.status == "created"
apply_payment.call(loan_id: payment.loan_id, payment_id: payment.id, amount: payment.amount)
payment.apply!
```

### 3. `LoanTransitionable` (Loan)

`app/models/concerns/loan_transitionable.rb` contiene exactamente el
`state_machine` que hoy vive inline en `app/models/loan.rb` (mismos estados,
mismo evento `paid`, mismo comportamiento con `run_action: false` en
`ApplyPayment`). `Loan` pasa a `include LoanTransitionable`.

## Testing

- Tests existentes de `apply_payment_test.rb`, `register_payment_test.rb`,
  `payment_created_listener_test.rb` deben seguir pasando sin cambios de
  comportamiento.
- `test/models/payment_test.rb`: agregar casos para las transiciones
  `validate_payment!` / `apply!` y que transiciones inválidas levanten error.
- Nuevo test para `UseCaseContainer`: mismos objetos memoizados en llamadas
  sucesivas a `UseCaseContainer[:register_payment]` /
  `UseCaseContainer[:apply_payment]`.
