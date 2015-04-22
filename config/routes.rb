Rails.application.routes.draw do
  post 'results/index'

  get 'welcome/index'

  root 'welcome#index'

end
