# mikr.us-frog-alpine-sing-box
自用 mikr.us 青蛙VPS 系统alpine 自动化部署sing-box 套CF的CDN实现双栈 和 WARP的V4出站规则
其他VPS可能不适用或者需要修改，请勿尝试，此脚本仅针对mikr.us frog 青蛙 VPS
青蛙VPS是V6入站 双栈出口的VPS V6是原生V6 V4是nat的
首先 域名托管CF 添加AAAA记录 开启小黄云 为申请ssl证书做准备
脚本默认部署acme.sh来申请证书和续签 使用默认http端口80来申请证书
运行脚本根据提示填写域名，填写前需要确定已经添加解析记录AAAA并开启小黄云
然后根据提示填写暴露公网端口号，不懂可以直接一路回车 脚本默认使用CF的回源端口号
最后会自动生成二维码和节点链接
warp设置建议如下图
<img width="1252" height="800" alt="9534a27b0272680c487294414a5044d" src="https://github.com/user-attachments/assets/b42bfd5e-b5c9-49c5-bce3-8c115fa7f955" />
