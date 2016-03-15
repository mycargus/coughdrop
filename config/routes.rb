Coughdrop::RESERVED_ROUTES = [
  'admin', 'etc', 'settings', 'status', 'reports', 'stats', 'search', 
  'messages', 'inbox', 'log', 'logs', 'session', 'sessions', 'imports', 
  'boards', 'users', 'groups', 'organizations', 'pages', 'people', 'videos', 
  'root', 'www', 'add', 'self', 'files', 'feeds', 
  'dev', 'auth', 'config', 'jobs', 'ssl', 
  'api', 'account', 'accounts', 'oauth', 'oauth_suggess', 'token', 
  'login', 'logout', 'register', 'profile', 'forgot_password', 
  'support', 'help', 'forum', 'talk', 'chat', 'feedback', 'faq', 
  'about', 'contact', 'info', 'docs', 'purchase', 'pricing', 'careers', 
  'news', 'styleguide', 'tour', 'compare', 'guides', 'partners', 
  'privacy', 'terms', 'hipaa', 'accessibility', 
  'js', 'css', 'scripts', 'script', 'pics', 'images',
  'find', 'unknown', 'nobody'
]
require 'resque/server'

Coughdrop::Application.routes.draw do
  # The priority is based upon order of creation: first created -> highest priority.
  # See how all your routes lay out with "rake routes".

  ember_handler = 'boards#index'
  board_id_regex = /[a-zA-Z0-9_-]+\/[a-zA-Z0-9_-]+|\d+_\d+/
  user_id_regex = /[a-zA-Z0-9_-]+/

  protected_resque = Rack::Auth::Basic.new(Resque::Server.new) do |username, password|
    u = User.find_by(:user_name => username)
    u && u.settings['admin'] && u.valid_password?(password)
  end
  mount protected_resque, :at => "/resque"

  root ember_handler
  get '/cache' => 'boards#cache'
  get '/privacy' => 'boards#privacy'
  get '/terms' => 'boards#terms'
  get '/jobs' => 'boards#jobs'
  
  # if Rails.env.production?
  # TODO: need to catch the update event to post a note encouraging the user to reload
    offline = Rack::Offline.configure :cache_interval => 120 do
      cache ActionController::Base.helpers.asset_path("application.css")
      cache ActionController::Base.helpers.asset_path("application.js")
      cache "/fonts/glyphicons-halflings-regular.eot"
      cache "/fonts/glyphicons-halflings-regular.svg"
      cache "/fonts/glyphicons-halflings-regular.ttf"
      cache "/fonts/glyphicons-halflings-regular.woff"
      cache "/fonts/OpenDyslexicAlta-Regular.otf"
      cache "/images/star.png"
      cache "/images/logo-small.png"
      cache "/images/logo-big.png"
      cache "/images/star_gray.png"
      cache "/images/folder.png"
      cache "/images/spinner.gif"
      cache "/images/talk.png"
      cache "/images/link.png"
      cache "/images/video.svg"
      cache "/images/app.png"
      cache "/images/orange.png"
      cache "/images/preview.png"
      cache "/images/stats.png"
      cache "/images/microphone.svg"
      cache "/images/upload.svg"
      cache "/images/camera.svg"
      cache "/images/delete.svg"
      cache "/images/square.svg"
      cache "/images/cc.png"
      cache "/images/pd.png"
      cache "/images/unknown_action.png"
      cache "/images/settings.png"
      cache "/images/jquery.minicolors.png"
      cache "/images/web_version.svg"
      cache "/images/ios_app_store.svg"
      cache "/images/google_play.png"
      cache "/offline"
      # cache other assets

      fallback({"/" => "/offline"})
      fallback({"/api/" => "/offline.json"})

      network "*"  
    end
    get "/application.manifest" => offline  
  # end
  
  get 'profile' => ember_handler
  get 'search/:query' => ember_handler
  get ':id/logs/:log_id' => ember_handler, :constraints => {:id => user_id_regex}
  
  get 'oauth2/token' => 'session#oauth'
  post 'oauth2/token/login' => 'session#oauth_login'
  post 'oauth2/token' => 'session#oauth_token'
  delete 'oauth2/token' => 'session#oauth_logout'
  get 'oauth2/token/status' => 'session#oauth_local', :as => 'oauth_local'
  post 'token' => 'session#token'

  get 'utterances/:id' => 'boards#utterance'  
  get ':id' => 'boards#user', :constraints => {:id => user_id_regex}
  get ':id' => 'boards#board', :constraints => {:id => board_id_regex}
  get ':id/icon' => 'boards#icon', :constraints => {:id => board_id_regex}
  
  get 'login' => ember_handler
  get ':id/confirm_registration/:key' => ember_handler, :constraints => {:id => user_id_regex}
  get ':id/password_reset/:key' => ember_handler, :constraints => {:id => user_id_regex}
  get 'api/v1/token_check' => 'session#token_check'
  
  scope 'api/v1', module: 'api' do
    post 'forgot_password' => 'users#forgot_password'
    post 'messages' => 'messages#create'
    
    resources :boards, :constraints => {:id => board_id_regex} do
      get 'stats' => 'boards#stats'
      post 'imports' => 'boards#import', on: :collection
      post 'unlink' => 'boards#unlink', on: :collection
      post 'stars' => 'boards#star'
      delete 'stars' => 'boards#unstar'
      post 'download' => 'boards#download'
      post 'rename' => 'boards#rename'
      post 'share_response' => 'boards#share_response'
      get 'copies' => 'boards#copies'
    end
    
    resources :users do
      get 'stats/daily' => 'users#daily_stats'
      get 'stats/hourly' => 'users#hourly_stats'
      post 'confirm_registration'
      post 'password_reset'
      post 'replace_board'
      post 'copy_board_links'
      post 'subscription' => 'users#subscribe'
      delete 'subscription' => 'users#unsubscribe'
      post 'flush/logs' => 'users#flush_logs'
      post 'flush/user' => 'users#flush_user'
      delete 'devices/:device_id' => 'users#hide_device'
      put 'devices/:device_id' => 'users#rename_device'
      post 'claim_voice' => 'users#claim_voice'
      post 'rename' => 'users#rename'
    end
    
    resources :images do
      get 'batch', on: :collection
      get 'upload_success'
    end
    
    get "buttonsets/:id" => "button_sets#show"
    get "boardversions" => "boards#history"
    
    resources :gifts
    
    resources :sounds do
      get 'upload_success'
    end
    
    resources :organizations do
      get 'managers'
      get 'users'
      get 'supervisors'
      get 'logs'
      get 'stats'
      get 'admin_reports'
    end
    
    resources :utterances do
      post 'share'
    end
    
    get "search/symbols" => "search#symbols"
    get "search/proxy" => "search#proxy"
    get "search/parts_of_speech" => "search#parts_of_speech"
    get "search/apps" => "search#apps"
    get "search/audio" => "search#audio"
    get "progress/:id" => "progress#progress"
    
    resources :logs do
      get 'lam'
    end
    
    post 'purchasing_event' => 'purchasing#event'
    post 'purchase_gift' => 'purchasing#purchase_gift'
  end

  # Example of regular route:
  #   get 'products/:id' => 'catalog#view'

  # Example of named route that can be invoked with purchase_url(id: product.id)
  #   get 'products/:id/purchase' => 'catalog#purchase', as: :purchase

  # Example resource route (maps HTTP verbs to controller actions automatically):
  #   resources :products

  # Example resource route with options:
  #   resources :products do
  #     member do
  #       get 'short'
  #       post 'toggle'
  #     end
  #
  #     collection do
  #       get 'sold'
  #     end
  #   end

  # Example resource route with sub-resources:
  #   resources :products do
  #     resources :comments, :sales
  #     resource :seller
  #   end

  # Example resource route with more complex sub-resources:
  #   resources :products do
  #     resources :comments
  #     resources :sales do
  #       get 'recent', on: :collection
  #     end
  #   end

  # Example resource route with concerns:
  #   concern :toggleable do
  #     post 'toggle'
  #   end
  #   resources :posts, concerns: :toggleable
  #   resources :photos, concerns: :toggleable

  # Example resource route within a namespace:
  #   namespace :admin do
  #     # Directs /admin/products/* to Admin::ProductsController
  #     # (app/controllers/admin/products_controller.rb)
  #     resources :products
  #   end
end
