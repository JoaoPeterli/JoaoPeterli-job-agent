Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "runs#index"

  resources :runs, only: %i[index create show] do
    post :cancel, on: :member
  end
end
