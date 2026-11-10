Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "runs#index"

  resource :profile, only: %i[edit update]
  resources :job_feedbacks, only: %i[create destroy]

  resources :runs, only: %i[index new create show destroy] do
    member do
      post :cancel
      post :redo
      post :restore
    end
  end
end
