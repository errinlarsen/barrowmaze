---
author: Maphismo
title:  Maphismo
pcid: Maphismo
layout: single
date:   2020-09-10 20:23:29 -0700
excerpt: Cleric 1 (played by Adam) DEAD
header:
  teaser: /assets/images/PC-MaphismoPortrait-thumb.png
author_profile: true
---

{% assign pc = site.data.pcs[page.pcid] %}

### {{ pc.class }} {{ pc.level }}
**Current Location:** {{ pc.location }}
**Current XP:** {{ pc.xp }}

![Maphismo (_Adam_)]({{ site.url }}{{ site.baseurl }}/assets/images/PC-Maphismo.2020.09.22.jpg)

## Posts

{% if paginator %}
  {% assign posts = paginator.posts %}
{% else %}
  {% assign posts = site.posts %}
{% endif %}

{% assign entries_layout = page.entries_layout | default: 'list' %}
{% assign filtered_posts = posts | where: 'author', page.author %}
<div class="entries-{{ entries_layout }}">
  {% for post in filtered_posts %}
    {% include archive-single.html type=entries_layout %}
  {% endfor %}
</div>

{% include paginator.html %}

<!-- {% assign filtered_posts = site.posts | where: 'author', page.author %} -->
<!-- {% for post in filtered_posts %} -->
<!--   - [{{ post.title }}]({{ post.url }}) -->
<!-- {% endfor %} -->
