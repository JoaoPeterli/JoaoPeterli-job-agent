Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "runs#index"

  resource :profile, only: %i[edit update]
  resources :job_feedbacks, only: %i[create destroy]
  resources :job_applications, only: :index, path: "candidaturas" do
    member do
      post :approve
      post :reject
    end
  end
  resources :job_postings, only: :index, path: "vagas" do
    get :similar, on: :collection, path: "parecidas"
  end

  resources :runs, only: %i[index new create show destroy] do
    member do
      post :cancel
      post :redo
      post :restore
    end
  end
end
