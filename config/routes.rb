Rails.application.routes.draw do
  namespace :v1 do
    namespace :external do
      resources :payments, only: [:create]
    end
  end

  resources :loans, only: [:show] do
    resources :payment_applications,
              path: "payment-applications",
              param: :payment_id,
              only: [:show, :update]
  end
end
