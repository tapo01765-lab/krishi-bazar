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
