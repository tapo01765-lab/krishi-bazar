from django.contrib import admin
from django.urls import path
from django.conf import settings
from django.conf.urls.static import static
from market import views

urlpatterns = [
    path('admin/', admin.site.urls),
    path('', views.home, name='home'),
    path('register/', views.register, name='register'),
    path('login/', views.user_login, name='login'),
    path('logout/', views.user_logout, name='logout'),
    path('add-product/', views.add_product, name='add_product'),
    path('orders/', views.my_orders, name='my_orders'),
    path('buy/<int:product_id>/', views.place_order, name='place_order'),
    path(
        'order-status/<int:order_id>/<str:new_status>/',
        views.update_order_status,
        name='update_order_status'
    ),
]

if settings.DEBUG:
    urlpatterns += static(
        settings.MEDIA_URL,
        document_root=settings.MEDIA_ROOT
    )
