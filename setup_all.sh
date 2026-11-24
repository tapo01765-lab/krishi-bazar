set -e

# 1. Models: existing products + new order system
cat > market/models.py <<'PY'
from django.db import models
from django.conf import settings


class Product(models.Model):
    CATEGORY_CHOICES = [
        ('ধান ও চাল', 'ধান ও চাল'),
        ('শাকসবজি', 'শাকসবজি'),
        ('ফলমূল', 'ফলমূল'),
        ('গম ও ভুট্টা', 'গম ও ভুট্টা'),
        ('আলু, পেঁয়াজ ও মসলা', 'আলু, পেঁয়াজ ও মসলা'),
        ('বীজ ও সার', 'বীজ ও সার'),
        ('মাছ', 'মাছ'),
        ('গবাদি পশু ও হাঁস-মুরগি', 'গবাদি পশু ও হাঁস-মুরগি'),
        ('কৃষি যন্ত্রপাতি', 'কৃষি যন্ত্রপাতি'),
        ('অন্যান্য', 'অন্যান্য'),
    ]

    UNIT_CHOICES = [
        ('কেজি', 'কেজি'),
        ('মণ', 'মণ'),
        ('বস্তা', 'বস্তা'),
        ('পিস', 'পিস'),
        ('লিটার', 'লিটার'),
        ('টন', 'টন'),
    ]

    seller = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name='products'
    )
    name = models.CharField(max_length=200)
    category = models.CharField(
        max_length=100,
        choices=CATEGORY_CHOICES,
        default='অন্যান্য'
    )
    price = models.DecimalField(max_digits=10, decimal_places=2)
    quantity = models.PositiveIntegerField()
    unit = models.CharField(
        max_length=20,
        choices=UNIT_CHOICES,
        default='কেজি'
    )
    description = models.TextField(blank=True)
    image = models.ImageField(
        upload_to='products/',
        blank=True,
        null=True
    )
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.name


class Order(models.Model):
    STATUS_CHOICES = [
        ('pending', 'অপেক্ষমাণ'),
        ('confirmed', 'গৃহীত'),
        ('completed', 'সম্পন্ন'),
        ('cancelled', 'বাতিল'),
    ]

    product = models.ForeignKey(
        Product, on_delete=models.SET_NULL,
        null=True, blank=True, related_name='orders'
    )
    product_name = models.CharField(max_length=200)
    buyer = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='buy_orders'
    )
    seller = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True, blank=True,
        related_name='sell_orders'
    )
    quantity = models.PositiveIntegerField()
    unit = models.CharField(max_length=20)
    unit_price = models.DecimalField(max_digits=10, decimal_places=2)
    total_price = models.DecimalField(max_digits=12, decimal_places=2)
    status = models.CharField(
        max_length=20, choices=STATUS_CHOICES, default='pending'
    )
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.product_name
PY

# 2. Views: one account for buying and selling
cat > market/views.py <<'PY'
from decimal import Decimal, InvalidOperation
from django.shortcuts import render, redirect, get_object_or_404
from django.contrib.auth import authenticate, login, logout
from django.contrib.auth.models import User
from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.db import transaction
from .models import Product, Order


def home(request):
    products = Product.objects.all().order_by('-created_at')
    return render(request, 'home.html', {'products': products})


def register(request):
    if request.user.is_authenticated:
        return redirect('home')

    if request.method == 'POST':
        username = request.POST.get('username', '').strip()
        email = request.POST.get('email', '').strip()
        password = request.POST.get('password', '')

        if not username or not password:
            messages.error(request, 'সব তথ্য পূরণ করুন।')
        elif User.objects.filter(username=username).exists():
            messages.error(request, 'এই ইউজারনেম আগে থেকেই আছে।')
        else:
            User.objects.create_user(
                username=username, email=email, password=password
            )
            messages.success(request, 'অ্যাকাউন্ট তৈরি হয়েছে। লগইন করুন।')
            return redirect('login')

    return render(request, 'register.html')


def user_login(request):
    if request.user.is_authenticated:
        return redirect('home')

    if request.method == 'POST':
        username = request.POST.get('username', '')
        password = request.POST.get('password', '')
        user = authenticate(
            request, username=username, password=password
        )

        if user is not None:
            login(request, user)
            return redirect(request.POST.get('next') or 'home')

        messages.error(request, 'ইউজারনেম অথবা পাসওয়ার্ড ভুল।')

    return render(request, 'login.html')


def user_logout(request):
    if request.method == 'POST':
        logout(request)
    return redirect('home')


@login_required
def add_product(request):
    if request.method == 'POST':
        try:
            price = Decimal(request.POST.get('price', '0'))
            quantity = int(request.POST.get('quantity', '0'))

            if price <= 0 or quantity <= 0:
                raise ValueError

            Product.objects.create(
                seller=request.user,
                name=request.POST.get('name', '').strip(),
                category=request.POST.get('category', 'অন্যান্য'),
                price=price,
                quantity=quantity,
                unit=request.POST.get('unit', 'কেজি'),
                description=request.POST.get('description', ''),
                image=request.FILES.get('image')
            )
            messages.success(request, 'পণ্য সফলভাবে যোগ হয়েছে।')
            return redirect('home')

        except (ValueError, InvalidOperation):
            messages.error(request, 'দাম ও পরিমাণ সঠিকভাবে লিখুন।')

    return render(request, 'add_product.html')


@login_required
@transaction.atomic
def place_order(request, product_id):
    if request.method != 'POST':
        return redirect('home')

    product = get_object_or_404(
        Product.objects.select_for_update(), id=product_id
    )

    try:
        quantity = int(request.POST.get('quantity', '0'))
    except ValueError:
        quantity = 0

    if product.seller_id == request.user.id:
        messages.error(request, 'নিজের পণ্য নিজে অর্ডার করা যাবে না।')
    elif quantity <= 0:
        messages.error(request, 'সঠিক পরিমাণ লিখুন।')
    elif quantity > product.quantity:
        messages.error(request, 'পর্যাপ্ত পণ্য মজুত নেই।')
    else:
        Order.objects.create(
            product=product,
            product_name=product.name,
            buyer=request.user,
            seller=product.seller,
            quantity=quantity,
            unit=product.unit,
            unit_price=product.price,
            total_price=product.price * quantity
        )
        product.quantity -= quantity
        product.save(update_fields=['quantity'])
        messages.success(request, 'আপনার অর্ডার গ্রহণ করা হয়েছে।')

    return redirect('home')


@login_required
def my_orders(request):
    buy_orders = Order.objects.filter(
        buyer=request.user
    ).order_by('-created_at')

    sell_orders = Order.objects.filter(
        seller=request.user
    ).order_by('-created_at')

    return render(request, 'orders.html', {
        'buy_orders': buy_orders,
        'sell_orders': sell_orders
    })


@login_required
@transaction.atomic
def update_order_status(request, order_id, new_status):
    if request.method != 'POST':
        return redirect('my_orders')

    order = get_object_or_404(
        Order.objects.select_for_update(),
        id=order_id,
        seller=request.user
    )

    if new_status not in ('confirmed', 'completed', 'cancelled'):
        messages.error(request, 'অবৈধ অর্ডার অবস্থা।')
    elif order.status == 'cancelled':
        messages.error(request, 'এই অর্ডার আগেই বাতিল হয়েছে।')
    else:
        if new_status == 'cancelled' and order.product_id:
            product = Product.objects.select_for_update().get(
                id=order.product_id
            )
            product.quantity += order.quantity
            product.save(update_fields=['quantity'])

        order.status = new_status
        order.save(update_fields=['status'])
        messages.success(request, 'অর্ডারের অবস্থা পরিবর্তন হয়েছে।')

    return redirect('my_orders')
PY

# 3. URLs
cat > krishibazar/urls.py <<'PY'
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
PY

# 4. Media settings
python - <<'PY'
from pathlib import Path
p = Path('krishibazar/settings.py')
s = p.read_text()
if 'MEDIA_URL =' not in s:
    s += "\nMEDIA_URL = '/media/'\nMEDIA_ROOT = BASE_DIR / 'media'\n"
p.write_text(s)
PY

# 5. Homepage
cat > market/templates/home.html <<'HTML'
<!DOCTYPE html>
<html lang="bn">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>কৃষি বাজার</title>
<style>
body{margin:0;font-family:sans-serif;background:#f0f7ed;color:#222}
header,footer{background:#16833b;color:white;text-align:center;padding:18px}
nav{background:#105d2b;padding:15px;text-align:center}
nav a{color:white;text-decoration:none;margin:8px;display:inline-block}
.container{max-width:900px;margin:20px auto;padding:12px}
.hero{text-align:center;padding:25px 10px}
.card{background:white;padding:18px;margin:12px 0;border-radius:12px;box-shadow:0 2px 8px #ccc}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:12px}
.btn,button{display:inline-block;background:#16833b;color:white;padding:11px 16px;border:0;border-radius:7px;text-decoration:none;cursor:pointer}
input{padding:10px;width:75px}
img{max-width:100%;height:auto;border-radius:8px}
small{color:#555}
</style>
</head>
<body>
<header>
<h1>🌾 কৃষি বাজার</h1>
<p>কৃষক ও ক্রেতার বিশ্বস্ত অনলাইন বাজার</p>
</header>
<nav>
<a href="/">হোম</a>
<a href="#products">পণ্য</a>
{% if user.is_authenticated %}
<a href="{% url 'add_product' %}">পণ্য যোগ করুন</a>
<a href="{% url 'my_orders' %}">আমার অর্ডার</a>
<form method="POST" action="{% url 'logout' %}" style="display:inline">
{% csrf_token %}<button type="submit">লগআউট</button>
</form>
{% else %}
<a href="{% url 'register' %}">রেজিস্ট্রেশন</a>
<a href="{% url 'login' %}">লগইন</a>
{% endif %}
</nav>

<div class="hero">
<h2>কৃষকের পণ্য কিনুন ও বিক্রি করুন</h2>
<p>একটি অ্যাকাউন্ট দিয়েই ক্রয় ও বিক্রয় করুন।</p>
{% if user.is_authenticated %}
<p>স্বাগতম, {{ user.username }}!</p>
<a class="btn" href="{% url 'add_product' %}">➕ পণ্য বিক্রি করুন</a>
<a class="btn" href="{% url 'my_orders' %}">আমার অর্ডার</a>
{% else %}
<a class="btn" href="{% url 'login' %}">লগইন</a>
<a class="btn" href="{% url 'register' %}">নতুন অ্যাকাউন্ট</a>
{% endif %}
</div>

<div class="container" id="products">
<h2>🌾 সকল কৃষিপণ্য</h2>
{% for message in messages %}
<p>{{ message }}</p>
{% endfor %}
<div class="grid">
{% for product in products %}
<div class="card">
{% if product.image %}
<img src="{{ product.image.url }}" alt="{{ product.name }}">
{% endif %}
<h3>{{ product.name }}</h3>
<p>ক্যাটাগরি: {{ product.category }}</p>
<p>দাম: ৳{{ product.price }} / {{ product.unit|default:"একক নেই" }}</p>
<p>মজুত: {{ product.quantity }} {{ product.unit|default:"" }}</p>
<p>{{ product.description }}</p>
{% if user.is_authenticated %}
{% if product.seller_id != user.id and product.quantity > 0 %}
<form method="POST" action="{% url 'place_order' product.id %}">
{% csrf_token %}
<label>কত {{ product.unit }} লাগবে?</label>
<input type="number" name="quantity" min="1"
max="{{ product.quantity }}" value="1" required>
<button type="submit">অর্ডার করুন</button>
</form>
{% elif product.seller_id == user.id %}
<small>আপনার নিজের পণ্য</small>
{% else %}
<small>পণ্য মজুত নেই</small>
{% endif %}
{% else %}
<a class="btn" href="{% url 'login' %}">লগইন করে কিনুন</a>
{% endif %}
</div>
{% empty %}
<p>এখনো কোনো পণ্য যোগ করা হয়নি।</p>
{% endfor %}
</div>
</div>
<footer>© ২০২৬ কৃষি বাজার</footer>
</body>
</html>
HTML

# 6. Add product form
cat > market/templates/add_product.html <<'HTML'
<!DOCTYPE html>
<html lang="bn">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>পণ্য যোগ করুন</title>
<style>
body{font-family:sans-serif;background:#f0f7ed;padding:15px}
.box{max-width:480px;margin:auto;background:white;padding:22px;border-radius:12px}
input,select,textarea,button{width:100%;padding:12px;margin:8px 0;box-sizing:border-box}
button{background:#16833b;color:white;border:0;border-radius:7px}
a{color:#16833b}
</style>
</head>
<body>
<div class="box">
<h2>🌾 নতুন পণ্য যোগ করুন</h2>
{% for message in messages %}<p>{{ message }}</p>{% endfor %}
<form method="POST" enctype="multipart/form-data">
{% csrf_token %}
<label>পণ্যের নাম</label>
<input name="name" required placeholder="যেমন: ধান">
<label>ক্যাটাগরি</label>
<select name="category" required>
<option value="ধান ও চাল">ধান ও চাল</option>
<option value="শাকসবজি">শাকসবজি</option>
<option value="ফলমূল">ফলমূল</option>
<option value="গম ও ভুট্টা">গম ও ভুট্টা</option>
<option value="আলু, পেঁয়াজ ও মসলা">আলু, পেঁয়াজ ও মসলা</option>
<option value="বীজ ও সার">বীজ ও সার</option>
<option value="মাছ">মাছ</option>
<option value="গবাদি পশু ও হাঁস-মুরগি">গবাদি পশু ও হাঁস-মুরগি</option>
<option value="কৃষি যন্ত্রপাতি">কৃষি যন্ত্রপাতি</option>
<option value="অন্যান্য">অন্যান্য</option>
</select>
<label>দাম (টাকা প্রতি একক)</label>
<input type="number" name="price" min="0.01" step="0.01" required>
<label>পরিমাণ</label>
<input type="number" name="quantity" min="1" required>
<label>পরিমাণের একক</label>
<select name="unit" required>
<option value="কেজি">কেজি</option>
<option value="মণ">মণ</option>
<option value="বস্তা">বস্তা</option>
<option value="পিস">পিস</option>
<option value="লিটার">লিটার</option>
<option value="টন">টন</option>
</select>
<label>পণ্যের ছবি</label>
<input type="file" name="image" accept="image/*">
<label>বিস্তারিত</label>
<textarea name="description" rows="4"></textarea>
<button type="submit">পণ্য যোগ করুন</button>
</form>
<p><a href="/">হোমে ফিরে যান</a></p>
</div>
</body>
</html>
HTML

# 7. Login
cat > market/templates/login.html <<'HTML'
<!DOCTYPE html>
<html lang="bn">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>লগইন | কৃষি বাজার</title>
<style>
body{font-family:sans-serif;background:#f0f7ed;padding:20px}
.box{max-width:380px;margin:40px auto;background:white;padding:24px;border-radius:12px}
input,button{width:100%;padding:13px;margin:9px 0;box-sizing:border-box}
button{background:#16833b;color:white;border:0;border-radius:7px}
</style></head>
<body><div class="box">
<h2>🌾 লগইন করুন</h2>
{% for message in messages %}<p>{{ message }}</p>{% endfor %}
<form method="POST">
{% csrf_token %}
<input name="username" placeholder="ইউজারনেম" required>
<input type="password" name="password" placeholder="পাসওয়ার্ড" required>
<button type="submit">লগইন</button>
</form>
<p>অ্যাকাউন্ট নেই? <a href="{% url 'register' %}">রেজিস্ট্রেশন</a></p>
<a href="/">হোমে ফিরে যান</a>
</div></body></html>
HTML

# 8. Registration
cat > market/templates/register.html <<'HTML'
<!DOCTYPE html>
<html lang="bn">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>রেজিস্ট্রেশন | কৃষি বাজার</title>
<style>
body{font-family:sans-serif;background:#f0f7ed;padding:20px}
.box{max-width:380px;margin:40px auto;background:white;padding:24px;border-radius:12px}
input,button{width:100%;padding:13px;margin:9px 0;box-sizing:border-box}
button{background:#16833b;color:white;border:0;border-radius:7px}
</style></head>
<body><div class="box">
<h2>🌾 নতুন অ্যাকাউন্ট</h2>
{% for message in messages %}<p>{{ message }}</p>{% endfor %}
<form method="POST">
{% csrf_token %}
<input name="username" placeholder="ইউজারনেম" required>
<input type="email" name="email" placeholder="ইমেইল (ঐচ্ছিক)">
<input type="password" name="password" placeholder="পাসওয়ার্ড" required>
<button type="submit">অ্যাকাউন্ট তৈরি করুন</button>
</form>
<p>অ্যাকাউন্ট আছে? <a href="{% url 'login' %}">লগইন করুন</a></p>
<a href="/">হোমে ফিরে যান</a>
</div></body></html>
HTML

# 9. Orders page
cat > market/templates/orders.html <<'HTML'
<!DOCTYPE html>
<html lang="bn">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>আমার অর্ডার | কৃষি বাজার</title>
<style>
body{font-family:sans-serif;background:#f0f7ed;padding:15px}
.box{max-width:750px;margin:auto}
.card{background:white;padding:16px;margin:12px 0;border-radius:10px}
button{padding:9px;background:#16833b;color:white;border:0;border-radius:6px;margin:4px}
</style></head>
<body><div class="box">
<h2>📦 আমার কেনা অর্ডার</h2>
{% for order in buy_orders %}
<div class="card">
<b>{{ order.product_name }}</b>
<p>পরিমাণ: {{ order.quantity }} {{ order.unit }}</p>
<p>মোট দাম: ৳{{ order.total_price }}</p>
<p>অবস্থা: {{ order.get_status_display }}</p>
</div>
{% empty %}<p>এখনো কোনো অর্ডার করেননি।</p>{% endfor %}

<h2>🌾 আমার বিক্রির অর্ডার</h2>
{% for order in sell_orders %}
<div class="card">
<b>{{ order.product_name }}</b>
<p>ক্রেতা: {{ order.buyer.username }}</p>
<p>পরিমাণ: {{ order.quantity }} {{ order.unit }}</p>
<p>মোট দাম: ৳{{ order.total_price }}</p>
<p>অবস্থা: {{ order.get_status_display }}</p>
{% if order.status != 'cancelled' and order.status != 'completed' %}
<form method="POST" action="{% url 'update_order_status' order.id 'confirmed' %}" style="display:inline">
{% csrf_token %}<button>অর্ডার গ্রহণ</button>
</form>
<form method="POST" action="{% url 'update_order_status' order.id 'completed' %}" style="display:inline">
{% csrf_token %}<button>সম্পন্ন</button>
</form>
<form method="POST" action="{% url 'update_order_status' order.id 'cancelled' %}" style="display:inline">
{% csrf_token %}<button>বাতিল</button>
</form>
{% endif %}
</div>
{% empty %}<p>এখনো কোনো বিক্রির অর্ডার নেই।</p>{% endfor %}
<p><a href="/">হোমে ফিরে যান</a></p>
</div></body></html>
HTML

echo "ফাইলগুলো তৈরি হয়েছে। এখন ডেটাবেজ আপডেট হচ্ছে..."
python manage.py makemigrations market
python manage.py migrate
python manage.py check
echo "সেটআপ শেষ!"
