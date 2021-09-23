Rails.application.routes.draw do
  root to: "tools#index"
  resources :tools do
    get :update_translations, on: :member
  end

  post 'pr_merge_webhooks', to: 'tools#update_merged'

  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
end
