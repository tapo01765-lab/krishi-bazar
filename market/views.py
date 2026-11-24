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
